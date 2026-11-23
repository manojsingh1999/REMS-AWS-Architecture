# Backup and Restore

**Status:** ✅ Aurora PITR (35 days), AWS Backup plan + Vault Lock + DR copy (`terraform/modules/backup`), restore script `database/scripts/restore-pitr.sh`, runbook `runbooks/postgres-restore.md`. ⚠️ No restore drill performed yet.

## Backup layers

| Layer | What | Retention | Where |
|---|---|---|---|
| Aurora continuous backup (PITR) | Both clusters | 35 days (`backup_retention_days`) | Primary region |
| AWS Backup daily | Resources tagged `backup=rems-critical` (Aurora, documents bucket) | `daily_retention_days`, schedule `cron(0 20 * * ? *)` (01:30 IST) | Vault + **copy to the DR vault** |
| AWS Backup monthly | Same | Cold storage after 30 days, deleted after 365 days. Schedule `cron(0 21 1 * ? *)` | Vault |
| Vault Lock | Backups can't be deleted before the minimum retention, even by admins | `enable_vault_lock`, `min/max_retention_days` | Both vaults |
| S3 | Versioning + CRR with RTC to the DR bucket | Lifecycle rules | DR region |
| Aurora Global DB | Storage-level replication (< 1 s typical lag) | continuous | DR region |

## Restore procedures

### A. Point-in-time restore (logical corruption, bad migration)

Always restore into a **new** cluster, never in place:

```bash
./database/scripts/restore-pitr.sh rems-prod-core 2026-11-21T09:45:00Z
# or the latest restorable time:
./database/scripts/restore-pitr.sh rems-prod-core latest
```

The timestamp above is the example from the script header. Use the incident's actual time. After validation, either repoint the RDS Proxy target to the restored cluster (full restore) or copy the affected rows back (partial restore). Follow `runbooks/postgres-restore.md`.

### B. Restore from AWS Backup

```bash
aws backup list-recovery-points-by-backup-vault --backup-vault-name <vault-name> \
  --query 'RecoveryPoints[?ResourceType==`Aurora`].[RecoveryPointArn,CreationDate]' --output table
aws backup get-recovery-point-restore-metadata --backup-vault-name <vault-name> --recovery-point-arn <arn>
aws backup start-restore-job --recovery-point-arn <arn> --iam-role-arn <backup-role-arn> \
  --metadata file://restore-metadata.json      # edit the metadata from the previous command
```

### C. Monthly restore drill (📋 to schedule)

1. `restore-pitr.sh rems-staging-core latest drill`
2. Run row counts / checksums on key tables against the source.
3. Delete the drill cluster. Record the time-to-restore against the 2 h RTO.

## Verification

```bash
aws rds describe-db-clusters --db-cluster-identifier rems-prod-core --query 'DBClusters[0].{earliest:EarliestRestorableTime,latest:LatestRestorableTime}'
aws backup list-backup-jobs --by-state COMPLETED --max-results 10
aws backup describe-backup-vault --backup-vault-name <vault-name> --query '{locked:Locked,min:MinRetentionDays}'
```

## Security considerations

Backups are encrypted with the `backup` CMK. Vault Lock in compliance mode is irreversible after `lock_changeable_for_days`. Confirm the retention values before that window closes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Restore fails: `KMSKeyNotAccessibleFault` | The restore role / account has no grant on the CMK |
| Backup job `EXPIRED` | Selection tag missing on the resource (`backup=rems-critical`) |
| Restored cluster isn't reachable | It's created without the proxy. Add it as a proxy target or connect directly from inside the VPC |
