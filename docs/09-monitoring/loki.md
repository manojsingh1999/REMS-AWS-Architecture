# Loki (logs)

**Status:** ✅ `monitoring/loki/values.yaml` (multi-tenant, S3 backend, retention). 🟡 Bucket and region are placeholders (`PLACEHOLDER-telemetry-bucket`, `PLACEHOLDER-region`). ⚠️ Not deployed.

## Objective

Store REMS platform logs (tenant `rems-platform`) and tenant log data in S3 with 30-day default retention (up to 90 days per tenant contract).

## Configuration (real values)

| Setting | Value |
|---|---|
| Storage | S3 (`bucketNames.chunks/ruler/admin` = telemetry bucket, prefix `loki/`) through the Pod Identity role `irsa_telemetry` |
| Retention | `retention_enabled: true`, `retention_period: 720h` (30 d). Per-tenant overrides with `2160h` (90 d) |
| Replicas | 3 (write/read paths), gp3 PVCs |
| Ingest | OTel Collector exporter `otlphttp/loki` → `http://loki-gateway.observability.svc/otlp` with header `X-Scope-OrgID: rems-platform` |

## Steps

1. Get the bucket name: `terraform -chdir=terraform/environments/prod output -json buckets | jq -r .telemetry`.
2. Replace the placeholders in `monitoring/loki/values.yaml` (and in `monitoring/tempo/values.yaml`, same bucket, different prefix).
3. Commit. ArgoCD syncs at wave -5.

## Verification

```bash
kubectl -n observability get pods -l app.kubernetes.io/name=loki
kubectl -n observability port-forward svc/loki-gateway 3100:80
curl -s -H 'X-Scope-OrgID: rems-platform' 'http://localhost:3100/loki/api/v1/labels' | jq .
aws s3 ls s3://<telemetry-bucket>/loki/ | head
```

## Security considerations

* Logs are redacted in the collector (`transform` processor statements) before storage. Review those rules for PII.
* Tenant isolation through `X-Scope-OrgID`. Never expose Loki directly to tenants. Access goes through REMS APIs, which set the org ID from the verified JWT.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `429 Too Many Requests` (`RemsTenantIngestionRateLimited`) | Tenant over `ingestion_rate_mb`. See `runbooks/telemetry-cost-spike.md` |
| `AccessDenied` to S3 | Pod Identity association for the `loki` service account is missing, or the KMS grant is missing |

## Rollback

Revert the values. Shortening retention deletes data at the next compaction, so it can't be undone.
