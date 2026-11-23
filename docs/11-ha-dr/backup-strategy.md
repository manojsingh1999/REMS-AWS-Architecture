# Backup Strategy

**Status:** ✅ Implemented (see [database backup and restore](../08-database/backup-and-restore.md) for the commands). ⚠️ No restore test executed.

## What is backed up, how and for how long

| Data | Class | Mechanism | Retention | Off-region copy |
|---|---|---|---|---|
| Aurora core + rag | System of record | PITR | 35 days | Global DB (continuous) |
| Aurora core + rag | System of record | AWS Backup daily / monthly (tag `backup=rems-critical`) | daily: `daily_retention_days`. Monthly: 365 days (cold after 30) | Daily copy to DR vault |
| S3 documents | System of record | Versioning + AWS Backup | Lifecycle (noncurrent 90 days) | CRR + RTC |
| S3 telemetry (Loki/Tempo) | Derived telemetry | none (by design) | 30–90 days | No |
| Valkey | Cache (not a system of record) | Daily snapshot | 7 days | No |
| Kubernetes state | Declarative | Git (platform repo + rems-microconfig) | Git history | GitHub |
| Secrets | Credentials | Secrets Manager versions | Version history | Replicas |
| Terraform state | IaC state | S3 versioning | Versions | CRR (prod) |
| Audit logs | Compliance | CloudWatch `/rems/<env>/audit` + org CloudTrail to Log Archive (Object Lock) | per `security/audit-logging.md` | Log Archive account |

## Immutability

* AWS Backup **Vault Lock** (`enable_vault_lock`): backups can't be deleted early, even by administrators. This protects against ransomware and insider risk.
* Log Archive bucket with S3 Object Lock (compliance mode).

## Testing cadence (📋 to start)

| Test | Frequency | Method |
|---|---|---|
| PITR restore of core into a new cluster | Monthly | `database/scripts/restore-pitr.sh rems-staging-core latest drill` |
| AWS Backup restore | Quarterly | `aws backup start-restore-job` |
| Regional switchover | Twice a year | `runbooks/dr-regional-failover.md` (planned `switchover`) |
| Git-based rebuild of a cluster | Yearly | New cluster + `scripts/bootstrap-cluster.sh` |
