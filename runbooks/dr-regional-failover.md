# Runbook: Regional disaster recovery (ap-south-1 → ap-southeast-1)

**Targets:** RPO 15 min and RTO 2 h for critical services (PDF). **Decision owner:** Incident Commander plus Head of Platform. Declare when the primary region has a confirmed multi-AZ or regional impairment expected to last more than 30 minutes, or on AWS's recommendation.

## Pre-conditions, continuously monitored

* Aurora Global DB lag < 60 s (alarm `…-global-replication-lag`), so the effective RPO is seconds.
* S3 CRR with RTC on `rag-documents` (99.99 % of objects within 15 min). Watch `ReplicationLatency`.
* Secrets replicated (Secrets Manager replicas), ECR replicated, DR EKS healthy (ArgoCD synced at 1 replica per service).
* A DR drill (planned switchover) has passed within the last 6 months.

## Procedure (budget about 75 min, within the 2 h RTO)

| Step | Time | Action |
|---|---|---|
| 1. Declare | T+0–15 | Page IC. Freeze deployments. Open the status page incident |
| 2. Promote data | T+15–25 | `database/scripts/aurora-failover.sh failover rems-prod-core-global <arn of rems-prod-dr-core>`, then the same for `rems-prod-rag-global`. Planned events use `switchover` (zero data loss) |
| 3. DR infra | T+25–40 | `cd terraform/environments/prod-dr && terraform init -reconfigure -backend-config=backend-dr-region.hcl`. Set `dr_promoted=true` and `prod_state_bucket`/`prod_state_region` to the replica bucket, then `terraform apply`. This creates the RDS Proxies and raises reader counts |
| 4. Scale apps | T+40–55 | Merge the prepared PR `dr-scale-up`, which removes the `autoscaling.minReplicas: 1` overrides from `helm/charts/*/values-prod-dr.yaml`. ArgoCD syncs and Karpenter adds nodes |
| 5. Verify | T+55–70 | Smoke tests: `scripts/smoke-test.sh https://app-dr.rems.example.com`. Check Grafana SLOs on the DR cluster, ExternalSecrets synced, and the LLM gateway (Bedrock in ap-southeast-1) |
| 6. Shift traffic | T+70–75 | Route 53 failover. Health checks flip automatically once primary health fails, or force it by setting the primary record health check to inverted. TTL is 60 s |
| 7. Communicate | T+75 | Update the status page. Users re-authenticate, because the DR Cognito pool federates to the same IdPs |

## Data notes

* Redis is not replicated. Caches warm up and queued jobs are re-enqueued from the Postgres outbox.
* Telemetry history before the failover stays in the primary region (RPO 24 h by design). New telemetry flows to DR stores immediately.

## Failback (planned, after primary recovery)

1. Rebuild the old primary as a Global DB secondary (`terraform apply` for `environments/prod`, which re-attaches it).
2. Wait for lag to reach 0, then run `aws rds switchover-global-cluster` (zero data loss) during a maintenance window.
3. Reverse steps 4–6 and reset `dr_promoted=false`.

## Drill

Twice a year: a planned switchover in a maintenance window, with RPO and RTO measured and recorded in the DR report.
