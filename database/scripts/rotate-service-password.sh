#!/usr/bin/env bash
# Zero-downtime password rotation for a REMS service login.
#   ./rotate-service-password.sh <env> <core|rag> <service>     e.g. prod core rems-api
# Order matters: new secret version (AWSPENDING) -> ALTER ROLE -> promote to AWSCURRENT.
# RDS Proxy reads the secret on new client connections; existing pooled connections stay valid.
set -euo pipefail

ENV_NAME="${1:?env}"; CLUSTER="${2:?core|rag}"; SERVICE="${3:?service}"
REGION="${AWS_REGION:-ap-south-1}"
SECRET_ID="rems/${ENV_NAME}/aurora/rems-${ENV_NAME}-${CLUSTER}/${SERVICE}"
MASTER_ID="rems/${ENV_NAME}/aurora/rems-${ENV_NAME}-${CLUSTER}/master"
CA_BUNDLE="${CA_BUNDLE:-/tmp/rds-global-bundle.pem}"
[[ -s "${CA_BUNDLE}" ]] || curl -sSfo "${CA_BUNDLE}" https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

current="$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_ID}" --query SecretString --output text)"
role="$(jq -r .username <<<"${current}")"
new_pw="$(aws secretsmanager get-random-password --region "${REGION}" --password-length 32 \
  --exclude-characters "'\"@/\\\` " --query RandomPassword --output text)"

token="$(uuidgen)"
aws secretsmanager put-secret-value --region "${REGION}" --secret-id "${SECRET_ID}" \
  --client-request-token "${token}" --version-stages AWSPENDING \
  --secret-string "$(jq --arg p "${new_pw}" '.password=$p' <<<"${current}")" >/dev/null

master="$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${MASTER_ID}" --query SecretString --output text)"
writer="$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "rems-${ENV_NAME}-${CLUSTER}" --query 'DBClusters[0].Endpoint' --output text)"
PGPASSWORD="$(jq -r .password <<<"${master}")" \
  psql "host=${writer} port=5432 dbname=postgres user=$(jq -r .username <<<"${master}") sslmode=verify-full sslrootcert=${CA_BUNDLE}" \
  -v ON_ERROR_STOP=1 -q <<<"ALTER ROLE ${role} WITH PASSWORD '${new_pw}';"

old_version="$(aws secretsmanager describe-secret --region "${REGION}" --secret-id "${SECRET_ID}" \
  --query 'VersionIdsToStages' --output json | jq -r 'to_entries[] | select(.value | index("AWSCURRENT")) | .key')"
aws secretsmanager update-secret-version-stage --region "${REGION}" --secret-id "${SECRET_ID}" \
  --version-stage AWSCURRENT --move-to-version-id "${token}" --remove-from-version-id "${old_version}"

echo "Rotated ${role}. External Secrets picks it up within refreshInterval (force: annotate the ExternalSecret)."
