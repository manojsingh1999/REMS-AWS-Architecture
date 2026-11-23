# Secrets Rotation

All secrets live in AWS Secrets Manager under `rems/<env>/…`, are encrypted with the `secrets` CMK, and are replicated to the DR region for prod.
Pods get them through External Secrets (refresh 1 h), mounted as files. Nothing is stored in Git or in container images.

| Secret | Path | Rotation | Procedure |
|---|---|---|---|
| Aurora service logins | `rems/<env>/aurora/<cluster>/<service>` | 90 days | 1. `ALTER ROLE … PASSWORD` via `database/scripts/rotate-service-password.sh` (writes a new secret version first) 2. RDS Proxy reads the new version immediately 3. ESO refreshes, pods reconnect through the proxy with no downtime |
| Aurora master | `rems/<env>/aurora/<cluster>/master` | 90 days, break-glass only | Same script with `--master`. Access to this secret alerts the security topic |
| Redis/Valkey AUTH | `rems/<env>/redis/<name>` | 180 days | `aws elasticache modify-replication-group --auth-token <new> --auth-token-update-strategy ROTATE` (old and new are both valid) → update secret → ESO refresh → wait 1 h → `--auth-token-update-strategy DELETE` for the old token |
| LLM provider API keys | `rems/<env>/llm/<provider>` | 90 days or on suspicion | Create a new key at the provider → put a new secret version → LLM gateway reloads → revoke the old key |
| Tenant DB scan credentials | `rems/<env>/tenant-db/<tenant>` | Owned by the customer. Reminder at 180 days | Customer rotates. Governance service re-reads on the next scan |

Emergency revocation of any secret: put a new version, then `kubectl annotate externalsecret <name> force-sync=$(date +%s) -n <ns>`, then roll the pods (`kubectl argo rollouts restart <svc> -n <ns>`).
