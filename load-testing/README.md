# REMS Load and Resilience Testing (k6 + AWS FIS)

Load tests run against **staging**, which mirrors prod topology: 3 AZs, 3 NAT gateways, Aurora writer + reader, Redis cluster mode.
Prod gets only scheduled game days with `ALLOW_PROD=yes`, using a synthetic test tenant.

| # | Scenario | k6 script | Fault injection | Pass criteria |
|---|---|---|---|---|
| 1 | Normal traffic (1× ≈ 165 req/s) | `scenarios/normal-load.js` | none | error < 0.5 %, read p95 < 300 ms, p99 < 500 ms |
| 2 | 5× peak (PDF assumption) | `scenarios/peak-5x.js` | none | same SLOs held for 30 min at 825 req/s, no HPA pinned at max |
| 3 | 10× spike within 5 min (review scenario) | `scenarios/spike-10x.js` | none | error < 1 %, p95 < 800 ms during ramp, < 300 ms within 5 min of plateau |
| 4 | Database bottleneck | `scenarios/db-bottleneck.js` | `chaos/run-chaos.sh aurora` (optional writer failover) | background user traffic error < 1 %. Saturation point recorded |
| 5 | AI provider failure / throttling | `scenarios/ai-provider-failure.js` | `chaos/run-chaos.sh ai-provider` | core API unaffected (< 0.5 % errors). Chat ≥ 95 % handled (answered or degraded) |
| 6 | Redis failure | `scenarios/redis-failure.js` | `chaos/run-chaos.sh redis` | error < 1 %, recovery < 2 min after promotion |
| 7 | Availability Zone failure | `scenarios/az-failure.js` | `chaos/run-chaos.sh az ap-south-1b` (FIS) | error < 0.5 % over 45 min, no manual action, p95 < 500 ms within 5 min |

## Running

```bash
# single runner (scenarios 1, 2, 5, 6, 7)
k6 run -e BASE_URL=https://app.staging.rems.example.com -e ACCESS_TOKEN="$TOKEN" load-testing/k6/scenarios/normal-load.js

# GitHub Actions (staging, environment-protected)
gh workflow run load-test.yml -f scenario=peak-5x

# distributed (scenarios 3 and 4 need > 3 000 VUs): k6-operator in the staging cluster
(cd load-testing/k6/scenarios && k6 archive spike-10x.js -O /tmp/spike-10x.tar)
kubectl -n loadtest create configmap rems-k6 --from-file=/tmp/spike-10x.tar
kubectl apply -f load-testing/k6-operator/testrun-spike-10x.yaml

# resilience drills (k6 + fault)
ENV=staging ACCOUNT_ID=222222222222 BASE_URL=https://app.staging.rems.example.com ACCESS_TOKEN="$TOKEN" \
  ./load-testing/chaos/run-chaos.sh az ap-south-1b
```

`config/endpoints.example.json` holds **placeholder routes** (assumption P7). Replace them with real REMS API routes from the OpenAPI spec before the first run.

## What to watch during a run

Grafana `REMS / SLO overview` and `REMS / Service RED`, KEDA/HPA replica counts, Karpenter `nodeclaims`, Aurora Performance Insights (top SQL, waits), RDS Proxy `DatabaseConnectionsCurrentlySessionPinned`, ElastiCache `EngineCPUUtilization`, and LLM gateway fallbacks.

## Results template (store under `results/<date>-<scenario>/`)

| Field | Example |
|---|---|
| Build / chart versions | rems-api sha-1a2b3c4, chart 1.0.0 |
| Peak achieved | 1 650 req/s |
| Error rate / p95 / p99 | 0.21 % / 240 ms / 410 ms |
| Max replicas reached (api, authz) | 28 / 9 |
| Nodes added by Karpenter / time to Ready | 9 / 52 s |
| Aurora writer CPU max / reader count | 61 % / 4 |
| Bottleneck found | e.g. `incidents/search` seq scan → index added |
| Pass / fail and follow-ups | PASS, 2 tickets |

Re-baseline the HPA targets and resource requests in `helm/charts/*/values-prod.yaml` from these results. The current requests are assumption A5.
