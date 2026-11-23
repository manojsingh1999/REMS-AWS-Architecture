# k6 Load Testing

**Status:** ✅ 7 scenarios (`load-testing/k6/scenarios/`) pass `k6 inspect`. k6-operator TestRun for distributed spikes. GitHub workflow `load-test.yml`. 🟡 API routes in `load-testing/config/endpoints.example.json` are **placeholders** (P7). ⚠️ No load test has been executed against an environment, so there are no results in `load-testing/results/`.

## Scenarios and pass criteria (`load-testing/README.md`)

| # | Scenario | Script | Pass criteria |
|---|---|---|---|
| 1 | Normal (1× ≈ 165 req/s) | `normal-load.js` | error < 0.5 %, read p95 < 300 ms, p99 < 500 ms |
| 2 | 5× peak | `peak-5x.js` | same SLOs for 30 min at 825 req/s, no HPA pinned at max |
| 3 | 10× spike in 5 min | `spike-10x.js` | error < 1 %, p95 < 800 ms during ramp, < 300 ms within 5 min of plateau |
| 4 | DB bottleneck | `db-bottleneck.js` | background error < 1 %, saturation point recorded |
| 5 | AI provider failure | `ai-provider-failure.js` | core API < 0.5 % errors, chat ≥ 95 % answered or degraded |
| 6 | Redis failure | `redis-failure.js` | error < 1 %, recovery < 2 min |
| 7 | AZ failure | `az-failure.js` | error < 0.5 % over 45 min, p95 < 500 ms within 5 min |

The 165 req/s baseline comes from 50 M events/day plus user traffic in `documentation/05-capacity-plan.md`.

## Configuration (environment variables read by `load-testing/k6/lib/config.js`)

| Variable | Default |
|---|---|
| `BASE_URL` | `https://app.staging.rems.example.com` |
| `ACCESS_TOKEN` | empty (obtain a test-tenant token from Cognito) |
| `BASE_RPS` | 165 |
| `DURATION` | 30m |
| `ENDPOINTS` | `../../config/endpoints.example.json` |

## Steps

1. Copy `load-testing/config/endpoints.example.json` to `endpoints.json` and replace every `PLACEHOLDER` route with real paths from the OpenAPI specs.
2. Get a token for a synthetic test tenant. Never use a real tenant.
3. Run:

   ```bash
   read -rs TOKEN
   k6 run -e BASE_URL=https://<staging-host> -e ACCESS_TOKEN="$TOKEN" -e ENDPOINTS=../../config/endpoints.json \
     --summary-export=load-testing/results/normal-load-$(date -u +%Y%m%d).json \
     load-testing/k6/scenarios/normal-load.js
   ```

   Through CI:

   ```bash
   gh workflow run load-test.yml -f scenario=peak-5x -f base_url=https://<staging-host>
   ```

   Distributed (spike / DB bottleneck, > 3 000 VUs):

   ```bash
   (cd load-testing/k6/scenarios && k6 archive spike-10x.js -O /tmp/spike-10x.tar)
   kubectl -n loadtest create configmap rems-k6 --from-file=/tmp/spike-10x.tar
   kubectl apply -f load-testing/k6-operator/testrun-spike-10x.yaml
   ```

## Verification

```bash
k6 inspect load-testing/k6/scenarios/normal-load.js     # offline syntax / options check (passes for all 7)
```

During a run, watch the `rems-service-red` and `rems-slo-overview` dashboards, plus `kubectl get hpa,scaledobjects,nodeclaims -A -w`.

## Safety

* Staging by default. `run-chaos.sh` refuses prod unless `ALLOW_PROD=yes` (game days only).
* WAF rate limits apply to load generators. Allow-list the runner IPs in staging, or run in-cluster (k6-operator).
* Bedrock costs: AI scenarios consume tokens. Budget them (staging Bedrock is estimated at 400 USD/month in the cost model).
