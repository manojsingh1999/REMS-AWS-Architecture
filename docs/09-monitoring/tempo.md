# Tempo (traces)

**Status:** ✅ `monitoring/tempo/values.yaml` (distributed mode, S3 backend, 30-day retention, metrics-generator for service graphs). 🟡 Bucket, region and S3 endpoint are placeholders. ⚠️ Not deployed.

## Configuration (real values)

| Setting | Value |
|---|---|
| Storage | S3 telemetry bucket, prefix `tempo/`. Pod Identity (service account `tempo`) |
| Retention | `block_retention: 720h` (30 d) |
| Ingest | OTel Collector `otlphttp/tempo` → `http://tempo-distributor.observability.svc:4318`, `X-Scope-OrgID: rems-platform` |
| Service graph | metrics-generator → Prometheus (service map in Grafana) |
| Sampling | Head sampling in the SDKs: `OTEL_TRACES_SAMPLER=parentbased_traceidratio`, ratio `0.1` in prod (chart value `otel.samplerRatio`) |

## Steps

1. Set `bucket`, `endpoint: s3.<region>.amazonaws.com`, `region` in `monitoring/tempo/values.yaml`.
2. Commit. ArgoCD syncs.

## Verification

```bash
kubectl -n observability get pods -l app.kubernetes.io/name=tempo
kubectl -n observability port-forward svc/tempo-query-frontend 3200:3200
curl -s -H 'X-Scope-OrgID: rems-platform' 'http://localhost:3200/api/search?limit=5' | jq '.traces | length'
```

🟡 Service names depend on the Tempo chart's naming. Confirm with `kubectl -n observability get svc`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No traces | Services aren't instrumented, or egress to the collector (4317/4318) is blocked (`allow-telemetry` policy) |
| Missing spans across services | Context propagation (W3C `traceparent`) not configured in a service |

## Rollback

Revert the values. Traces are disposable telemetry.
