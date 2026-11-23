# PostgreSQL (Aurora) Setup

**Status:** ✅ Terraform `terraform/modules/aurora-postgresql` (2 clusters per environment), SQL in `database/sql/`, bootstrap script `database/scripts/bootstrap-roles.sh`. SQL is parsed with the PostgreSQL 16 parser (pglast) and scripts are shellcheck-clean. ⚠️ Never run against a real cluster.

## Objective

Two Aurora PostgreSQL 16 clusters per environment: `rems-<env>-core` (OLTP for API, authz, governance and the LLM gateway spend DB) and `rems-<env>-rag` (pgvector for Savvy/RCA). Least-privilege logins, RLS, and pooled access through RDS Proxy.

## Prerequisites

* Environment applied (`terraform/environments/<env>`).
* A host inside the VPC: an SSM session to a bastion, or a one-off Kubernetes Job. psql 16, jq and AWS CLI v2. Permission to read `rems/<env>/aurora/*` secrets.

## AWS services

Aurora PostgreSQL, RDS Proxy, Secrets Manager, KMS, CloudWatch (Performance Insights, enhanced monitoring), Application Auto Scaling (readers).

## Terraform configuration (prod, `terraform/environments/prod/main.tf`)

```hcl
  aurora_core = {
    instance_class    = "db.r7g.2xlarge"
    reader_count      = 2
    io_optimized      = true
    autoscaling_max   = 5
    pi_retention_days = 731
  }
  aurora_rag = {
    instance_class    = "db.r7g.xlarge"
    reader_count      = 1
    io_optimized      = true
    autoscaling_max   = 3
    pi_retention_days = 31
  }
```

`backup_retention_days` defaults to 35 (`terraform/modules/rems-environment/variables.tf`). The rag cluster sets `statement_timeout_ms = 120000` for index builds and vector search.

## Steps

1. Apply Terraform (creates the clusters, proxy, parameter groups, master and service secrets).
2. From a host in the VPC, bootstrap the databases, roles, grants, RLS and pgvector:

   ```bash
   export AWS_REGION=ap-south-1
   ./database/scripts/bootstrap-roles.sh prod core
   ./database/scripts/bootstrap-roles.sh prod rag
   ```

   The script is idempotent. For `core` it applies `01-roles-and-databases.sql` and `01b-database-grants.sql` (in `postgres`), then `02-schema-privileges.sql` in rems_api, rems_authz and rems_governance (role names substituted with sed), then `03-row-level-security.sql` in rems_api. For `rag` it applies `04-pgvector-rag.sql` in rems_savvy (`embedding vector(1024)`, HNSW index `m = 16, ef_construction = 64`, cosine ops).

3. Point services at the **proxy** endpoints (`terraform output -json aurora` → `core_proxy_endpoint`, `core_proxy_ro_endpoint`, `rag_proxy_endpoint`). How each service receives the endpoint is application configuration (pending, P6). The secret JSON contains the credentials.

## Verification

```bash
aws rds describe-db-clusters --db-cluster-identifier rems-prod-core \
  --query 'DBClusters[0].{status:Status,engine:EngineVersion,members:DBClusterMembers[].{id:DBInstanceIdentifier,writer:IsClusterWriter}}'
aws rds describe-db-proxies --query 'DBProxies[].{n:DBProxyName,s:Status,tls:RequireTLS}'
# From inside the VPC:
SECRET=$(aws secretsmanager get-secret-value --secret-id rems/prod/aurora/rems-prod-core/rems-api --query SecretString --output text)
PGPASSWORD=$(jq -r .password <<<"$SECRET") psql "host=<core_proxy_endpoint> dbname=rems_api user=rems_api sslmode=verify-full sslrootcert=/tmp/rds-global-bundle.pem" -c 'select current_user, version();'
```

The service secret JSON (written by `modules/aurora-postgresql`) has the keys `engine`, `username`, `password`, `host` (the proxy endpoint when the proxy exists), `port` (5432) and `dbname`.

## Security considerations

* `rds.force_ssl = 1`. Proxy `require_tls = true`. Storage and PI encrypted with the `aurora` CMK.
* Services never use the master login. Each has its own DB and role with no `CREATEDB` / `CREATEROLE`.
* Security groups: 5432 only from the EKS cluster SG and the proxy SG.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `bootstrap-roles.sh`: `could not connect` | Not inside the VPC, or the SG doesn't allow your host. Use a Job in the cluster |
| `FATAL: password authentication failed` through the proxy | The proxy caches the secret. Wait for the refresh, or check that the proxy auth has that secret ARN |
| `permission denied for schema` | `02-schema-privileges.sql` not applied for that DB. Re-run the bootstrap |
| High `DatabaseConnections` | See [connection pooling](connection-pooling.md) and `runbooks/postgres-bottleneck.md` |

## Rollback

Schema/role SQL is idempotent and additive. Data-level rollback goes through [backup and restore](backup-and-restore.md). With `deletion_protection = true` (staging, prod) a cluster can't be destroyed by accident.
