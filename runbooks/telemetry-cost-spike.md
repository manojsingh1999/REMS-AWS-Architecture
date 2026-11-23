# Runbook: Telemetry volume makes infrastructure costs unexpectedly high

**Alerts:** `RemsTenantLogVolumeSpike`, `RemsActiveSeriesGrowth`, `RemsTenantIngestionRateLimited`, AWS Budgets 80 %/100 %, and Cost Anomaly Detection (service = EC2, S3 or Data Transfer).

## Where telemetry cost comes from

| Driver | Signal |
|---|---|
| Loki ingestion (CPU on write path, S3 PUTs, chunk cache) | `loki_distributor_bytes_received_total` by tenant |
| Metric cardinality (vmstorage memory and disk) | VictoriaMetrics active series, `vm_new_timeseries_created_total` |
| Traces | `tempo_distributor_bytes_received_total` by tenant |
| NAT / cross-AZ transfer | Cost Explorer: NatGateway-Bytes, DataTransfer-Regional-Bytes |
| CloudWatch Logs (should be small: audit and control plane only) | `IncomingBytes` by log group |

## Diagnose

1. Grafana Explore: `topk(10, rems:loki_ingested_bytes:rate1h_by_tenant)`. Find the tenant and the stream labels (often debug logging or a new label with unbounded values).
2. VictoriaMetrics cardinality explorer (`/select/<account>/vmui/#/cardinality`): find the top metric names and label pairs.
3. Cost Explorer grouped by usage type and tag `Environment`.

## Levers (from immediate to structural)

| Lever | Where | Effect |
|---|---|---|
| Per-tenant ingestion limits (already enforced, data above the limit is dropped) | Loki `runtimeConfig.overrides`, Tempo `global_overrides`, vminsert `maxLabelsPerTimeseries` | Caps the blast radius immediately |
| Drop or relabel high-cardinality labels | Prometheus `writeRelabelConfigs`, OTel `transform` / `filter` processors | -30–80 % series |
| Sampling | OTel `OTEL_TRACES_SAMPLER_ARG` (prod 0.1), tail sampling for errors only | -90 % traces |
| Retention by contract | Loki `retention_period` per tenant (30 d default, 90 d premium) | Linear S3 savings |
| Storage tiering | S3 lifecycle (IA after 30 d), Intelligent-Tiering, expiry at 90 d | -40 % storage |
| Avoid NAT for AWS traffic | S3 gateway endpoint, interface endpoints (already in place). Check for anything bypassing them | Removes NAT data-processing charges |
| Commercial | Usage-based pricing tier or ingestion cap per tenant contract | Aligns cost with revenue |

## Follow-up

Add the tenant's new baseline to capacity planning, and make sure cost alerts route to both platform and FinOps owners.
