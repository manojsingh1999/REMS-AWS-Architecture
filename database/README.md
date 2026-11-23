# REMS Database Layer

Design rationale and diagrams: [`architecture/06-data-architecture.md`](../architecture/06-data-architecture.md). Infrastructure: `terraform/modules/aurora-postgresql` and `terraform/modules/elasticache-redis`.

## PostgreSQL (Aurora PostgreSQL 16)

| Requirement | Implementation |
|---|---|
| High availability | Writer + 2 readers across 3 AZs (prod). Storage is replicated 6 ways. Automatic failover < 30 s. Promotion tiers are set |
| Replication | Readers in-region (auto scaling 2→5 on CPU 60 %). **Aurora Global Database** to ap-southeast-1 (lag alarm at > 60 s) |
| Connection pooling | **RDS Proxy** per cluster (RW + RO endpoints, TLS required, 80 % max connections, session pinning kept on SET for tenant safety) plus small app pools (≤ 10 per pod) |
| Backups | Continuous backup with PITR for 35 days, AWS Backup daily → DR-region vault (Vault Lock), and monthly copies kept 1 year |
| Encryption | KMS CMK at rest (storage, snapshots, Performance Insights). `rds.force_ssl=1`, clients use `sslmode=verify-full` |
| Monitoring | Performance Insights, Enhanced Monitoring 15 s, slow-query log (> 500 ms) + `auto_explain`, `pg_stat_statements`, CloudWatch alarms (CPU, connections, replica lag, global lag) |
| Disaster recovery | Global DB secondary (RPO ≈ seconds, RTO ~5 min for the DB tier). PITR to a new cluster for logical corruption |
| Tenant isolation | `sql/03-row-level-security.sql` (RLS + FORCE + same-tenant composite FK) |
| Vector search | Separate `rems-rag` cluster with pgvector HNSW (`sql/04-pgvector-rag.sql`) |

### Files

```
sql/01-roles-and-databases.sql   idempotent roles (owners NOLOGIN, per-service logins, migrator, readonly, monitoring)
sql/01b-database-grants.sql      CONNECT grants after the databases exist
sql/02-schema-privileges.sql     schema + default privileges (DML only for apps)
sql/03-row-level-security.sql    tenant RLS pattern (rems_api)
sql/04-pgvector-rag.sql          Savvy documents/chunks, HNSW index, RLS (rems_savvy on rems-rag)
scripts/bootstrap-roles.sh       applies all of the above + sets passwords from Secrets Manager
scripts/rotate-service-password.sh  zero-downtime rotation
scripts/restore-pitr.sh          PITR restore into a new cluster
scripts/aurora-failover.sh       az-test | switchover | failover (Global DB)
```

### Commands

```bash
# one-time after terraform apply (from a host in the VPC, e.g. SSM session on the ops bastion)
AWS_REGION=ap-south-1 ./database/scripts/bootstrap-roles.sh prod core
AWS_REGION=ap-south-1 ./database/scripts/bootstrap-roles.sh prod rag

# monthly restore drill (staging)
./database/scripts/restore-pitr.sh rems-staging-core latest drill

# quarterly AZ failover drill
./database/scripts/aurora-failover.sh az-test rems-staging-core
```

## Redis / Valkey (ElastiCache)

See [`redis/README.md`](redis/README.md).
