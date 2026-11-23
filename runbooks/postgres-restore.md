# Runbook: PostgreSQL restore (logical corruption, bad migration, accidental delete)

Global DB and Multi-AZ protect against infrastructure loss, not against bad writes, which replicate instantly. Use point-in-time restore (PITR) for those.

## Decide the restore point

Find the last good time from the audit log, the deploy time of the bad migration (ArgoCD history), or `pg_stat_statements` / CloudTrail for the destructive statement. Aim for 1–2 minutes before the event.

## Restore into a new cluster (never in place)

```bash
./database/scripts/restore-pitr.sh rems-prod-core 2026-11-21T09:45:00Z inc1234
# -> rems-prod-core-inc1234 ready in 10-25 min
```

## Option A: partial restore (preferred, no downtime)

1. Connect to the restored cluster with the break-glass master secret.
2. Export only the affected rows. Example for one tenant's incidents:
   `\copy (SELECT * FROM rems.incidents WHERE tenant_id = '…' AND created_at < '…') TO 'incidents.csv' CSV`
   (set `app.tenant_id`, since RLS also applies to the master user through FORCE. Alternatively use the table-owner role with an explicit policy bypass approved by security)
3. Load the rows into prod through a reviewed SQL script inside a transaction, and verify counts or checksums.

## Option B: full cutover (large corruption)

1. Put REMS in maintenance mode (frontend banner, API returns 503 for writes).
2. Point the RDS Proxy target to the restored cluster: `aws rds register-db-proxy-targets --db-proxy-name rems-prod-core --db-cluster-identifiers rems-prod-core-inc1234`, after deregistering the old one.
3. Run the smoke tests, end maintenance mode, then update Terraform (import or rename) so state matches reality.
4. Re-create the Global DB secondary from the new primary.

## Verification and cleanup

Run checksums per tenant on key tables. Keep the restored cluster for 7 days, then delete it (deletion protection is on, so remove it via break-glass). Write the postmortem.

**RPO note:** PITR granularity is about 5 minutes (transaction log upload), which is within the 15-minute RPO.
