# REMS Runbooks

Every alert carries a `runbook_url` pointing to one of these pages. They also answer the PDF's **architecture review scenarios**.

| PDF review scenario | Runbook | Automatic response | Human action |
|---|---|---|---|
| One AZ becomes unavailable | [az-failure.md](az-failure.md) | ALB, Aurora, ElastiCache and Karpenter fail over and reschedule | Verify, then stop voluntary disruption |
| REMS API traffic 10× in 5 min | [traffic-spike.md](traffic-spike.md) | Overprovision buffer, KEDA, Karpenter, WAF rate limits | Raise limits if pinned at max |
| PostgreSQL is the bottleneck | [postgres-bottleneck.md](postgres-bottleneck.md) | Reader auto scaling, RDS Proxy queueing, statement timeouts | Kill or optimize top SQL, scale writer |
| AI provider down / rate-limiting | [ai-provider-outage.md](ai-provider-outage.md) | Gateway retries, circuit breaker, fallback, degraded mode | Quota increase / provider comms |
| Cross-tenant access attempt | [cross-tenant-access-attempt.md](cross-tenant-access-attempt.md) | OPA deny + RLS returns 0 rows + audit + alert | Security investigation |
| Deployment introduces a regression | [bad-deployment-rollback.md](bad-deployment-rollback.md) | Argo Rollouts analysis aborts the canary | Revert / rollback workflow |
| Compromised AI/MCP tool tries an infra operation | [compromised-mcp-tool.md](compromised-mcp-tool.md) | OPA deny, RBAC/IAM/SCP make it impossible, alert | Contain, revoke tokens, forensics |
| Telemetry volume makes costs spike | [telemetry-cost-spike.md](telemetry-cost-spike.md) | Per-tenant ingestion limits drop excess | Tune limits / sampling, talk to tenant |

Additional runbooks: [dr-regional-failover.md](dr-regional-failover.md), [postgres-restore.md](postgres-restore.md), [redis-failure.md](redis-failure.md), [slo-burn-rate.md](slo-burn-rate.md).

Conventions: commands assume `aws` and `kubectl` are configured through IAM Identity Center (role `OnCall` or `PlatformAdmin`) and the cluster context `rems-<env>`. Prod changes go through Git (GitOps) unless the runbook says "break-glass".
