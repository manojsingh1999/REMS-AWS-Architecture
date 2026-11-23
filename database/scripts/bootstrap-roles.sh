#!/usr/bin/env bash
# Bootstrap REMS databases, roles, privileges, RLS and pgvector on an Aurora cluster.
# Idempotent. Run from a host inside the VPC (SSM session on a bastion or a one-off Kubernetes Job)
# with permissions to read rems/<env>/aurora/* secrets.
#
#   ./bootstrap-roles.sh <env> <core|rag>
#
# Requires: aws CLI v2, jq, psql 16, the RDS CA bundle (downloaded automatically if absent).
set -euo pipefail

ENV_NAME="${1:?usage: $0 <env> <core|rag>}"
CLUSTER="${2:?usage: $0 <env> <core|rag>}"
REGION="${AWS_REGION:-ap-south-1}"
SQL_DIR="$(cd "$(dirname "$0")/../sql" && pwd)"
CLUSTER_ID="rems-${ENV_NAME}-${CLUSTER}"
SECRET_PREFIX="rems/${ENV_NAME}/aurora/${CLUSTER_ID}"
CA_BUNDLE="${CA_BUNDLE:-/tmp/rds-global-bundle.pem}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

secret() { aws secretsmanager get-secret-value --region "${REGION}" --secret-id "$1" --query SecretString --output text; }

if [[ ! -s "${CA_BUNDLE}" ]]; then
  curl -sSfo "${CA_BUNDLE}" https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
fi

MASTER_JSON="$(secret "${SECRET_PREFIX}/master")"
# Connect to the writer endpoint directly (DDL should not go through RDS Proxy).
HOST="$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER_ID}" --query 'DBClusters[0].Endpoint' --output text)"
export PGHOST="${HOST}" PGPORT=5432 PGSSLMODE=verify-full PGSSLROOTCERT="${CA_BUNDLE}"
PGUSER="$(jq -r .username <<<"${MASTER_JSON}")"
PGPASSWORD="$(jq -r .password <<<"${MASTER_JSON}")"
export PGUSER PGPASSWORD

run_sql() { # db file [sed-expression]
  local db="$1" file="$2" expr="${3:-}"
  log "apply ${file##*/} -> ${db}"
  if [[ -n "${expr}" ]]; then
    sed -e "${expr}" "${file}" | psql -v ON_ERROR_STOP=1 -q -d "${db}"
  else
    psql -v ON_ERROR_STOP=1 -q -d "${db}" -f "${file}"
  fi
}

create_db() { # name owner
  psql -v ON_ERROR_STOP=1 -q -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$1'" | grep -q 1 \
    || psql -v ON_ERROR_STOP=1 -q -d postgres -c "CREATE DATABASE $1 OWNER $2"
}

set_password() { # role secret-name   (password travels via stdin, never argv)
  local role="$1" pw
  pw="$(secret "$2" | jq -r .password | sed "s/'/''/g")"
  printf "ALTER ROLE %s WITH PASSWORD '%s';\n" "${role}" "${pw}" | psql -v ON_ERROR_STOP=1 -q -d postgres
  log "password set for ${role}"
}

case "${CLUSTER}" in
  core)
    run_sql postgres "${SQL_DIR}/01-roles-and-databases.sql"
    create_db rems_api rems_api_owner
    create_db rems_authz rems_authz_owner
    create_db rems_governance rems_governance_owner
    create_db rems_llmgw rems_llmgw # LiteLLM runs its own (Prisma) migrations, so it owns its database
    run_sql postgres "${SQL_DIR}/01b-database-grants.sql"
    run_sql rems_api        "${SQL_DIR}/02-schema-privileges.sql"
    run_sql rems_authz      "${SQL_DIR}/02-schema-privileges.sql" 's/rems_api_owner/rems_authz_owner/g; s/rems_api\b/rems_authz/g'
    run_sql rems_governance "${SQL_DIR}/02-schema-privileges.sql" 's/rems_api_owner/rems_governance_owner/g; s/rems_api\b/rems_governance/g'
    run_sql rems_api        "${SQL_DIR}/03-row-level-security.sql"
    set_password rems_api        "${SECRET_PREFIX}/rems-api"
    set_password rems_authz      "${SECRET_PREFIX}/authorization-service"
    set_password rems_governance "${SECRET_PREFIX}/data-governance"
    set_password rems_llmgw      "${SECRET_PREFIX}/llm-gateway"
    ;;
  rag)
    psql -v ON_ERROR_STOP=1 -q -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rems_savvy_owner') THEN CREATE ROLE rems_savvy_owner NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rems_savvy') THEN
    CREATE ROLE rems_savvy LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS CONNECTION LIMIT 300;
  END IF;
END
$$;
SQL
    create_db rems_savvy rems_savvy_owner
    psql -v ON_ERROR_STOP=1 -q -d postgres -c "REVOKE ALL ON DATABASE rems_savvy FROM PUBLIC; GRANT CONNECT ON DATABASE rems_savvy TO rems_savvy;"
    run_sql rems_savvy "${SQL_DIR}/04-pgvector-rag.sql"
    set_password rems_savvy "${SECRET_PREFIX}/metadata-rca"
    ;;
  *)
    echo "cluster must be core or rag" >&2
    exit 2
    ;;
esac

log "bootstrap of ${CLUSTER_ID} complete"
