# Scalability Plan: Capacity Estimates, Triggers, Bottlenecks, Load Testing

## 1. Demand model (PDF inputs + documented assumptions)

| Quantity | Average | Peak (5×) | Spike (10× in 5 min) | Source |
|---|---|---|---|---|
| Operational events | 50 M/day = **579 ev/s** | 2 894 ev/s | 5 787 ev/s | PDF |
| Ingest requests (batches of 40) | 15 req/s | 72 req/s | 145 req/s | assumption |
| User-facing API requests (100 tenants) | 150 req/s | 750 req/s | 1 500 req/s | A5 |
| Raw event volume | 50 GB/day | | | A4 (1 KB/event) |
| Compressed telemetry in S3 | ~6 GB/day → ~0.54 TB at 90 d | | | Loki/Tempo ~8–10× compression |
| Active metric series | 1 M (20 tenants) → 5 M (100 tenants) | | | 50 k series per tenant (assumption) |
| LLM tokens | ~48 M/day RCA + ~34 M/day chat | | | `ai-infrastructure/README.md` |

## 2. Capacity per component (prod, 100 tenants)

| Component | Unit capacity (to verify with k6) | Needed at peak | N+1 AZ rule (×1.5) | Configured min–max |
|---|---|---|---|---|
| rems-api | 100 req/s per pod @ 65 % CPU | 9 pods (900 req/s) | 14 | **6–40** (10× spike ≈ 17 pods → 25 with AZ rule) |
| authorization-service | 400 checks/s per pod (decision cache in Redis) | 3 | 5 | 3–20 |
| rems-frontend | 1 000 req/s per nginx pod (static) | 1 | 2 | 3–10 |
| chat-engine | 20 concurrent streams per pod | 150 sessions → 8 | 12 | 3–20 |
| metadata-rca | 10 concurrent RCA jobs per pod | ~8 | 12 | 2–12 |
| llm-gateway | ~100 concurrent upstream calls per pod | 4 | 6 | 3–12 |
| OTel collector | 20 k spans or logs/s per pod | 3 | 5 | 3–30 |
| Aurora rems-core writer (r7g.2xlarge, 8 vCPU) | ~5 k simple writes/s, ~1 500 connections behind the proxy | ~700 writes/s | readers 2→5 | 1 writer + 2–5 readers |
| Aurora rems-rag (r7g.xlarge) | HNSW top-8 < 20 ms for < 10 M vectors | ~100 queries/s | readers 1→3 | 1 writer + 1–3 readers |
| RDS Proxy | multiplexes ~1 000 client connections onto ~300 DB connections | rems-api 40 pods × 10 = 400 | | 80 % of max_connections |
| Valkey (3 shards r7g.large) | ~100 k ops/s per shard | ~10 k ops/s | 1 replica per shard | scale shards online |
| VictoriaMetrics (3 vmstorage) | ~1 M active series per 4 GB RAM | 5 M series | RF = 2 | 3 → 6 vmstorage at 70 % memory |
| Loki write path | ~10 MB/s per writer | 3 MB/s average, 15 MB/s peak | | 3–12 writers |
| EKS / Karpenter | NodePool CPU limits: general 400, ai 200, obs 160, workers 300 vCPU | ~120 vCPU | | raise limits via PR |

## 3. Scaling triggers

| Layer | Trigger | Reaction time |
|---|---|---|
| Pods (API) | KEDA: RPS per pod > 80, or CPU > 65 % | 15–30 s |
| Pods (AI) | KEDA: in-flight requests per pod (chat > 20, RCA > 10) | 15–30 s |
| Pods (workers) | KEDA: Redis list length > 500 per replica | 15 s |
| Nodes | Karpenter: pending pods (bin-packing across 20+ instance types, Spot + OD) | 45–90 s |
| Warm buffer | Overprovisioning pause pods (3 × 2 vCPU) preempted instantly | < 5 s |
| DB readers | Aurora auto scaling: reader CPU > 60 % | 8–12 min |
| DB writer | Manual (runbook): sustained CPU > 70 % or IO waits → instance class step-up | 15–20 min |
| Cache | Manual: memory > 70 % or CPU > 60 % → add shard (online) | 10–30 min |
| Telemetry stores | HPA on distributors/inserters. vmstorage/Loki PVC > 80 % → expand (gp3 online resize) | minutes |
| LLM | Gateway: per-deployment RPM/TPM. Bedrock quota request when > 60 % of quota at p95 | days (quota) |

## 4. Known bottlenecks and mitigations

| # | Bottleneck | Symptom | Mitigation built in | Next step |
|---|---|---|---|---|
| B1 | Aurora writer (all OLTP on one primary) | Write latency, CPU | RDS Proxy, readers for reads, separate RAG cluster, statement timeouts | Partition hot tables. Move a heavy tenant to a silo cluster. Aurora Limitless if needed |
| B2 | Bedrock quota | 429s, fallbacks | Gateway routing by RPM/TPM, per-tenant limits, cache, tiering | Quota increase, cross-region inference profiles, Provisioned Throughput |
| B3 | Cardinality explosion (metrics) | vmstorage memory, cost | `maxLabelsPerTimeseries`, relabel drops, alerts | Per-tenant series limits (`-maxSeriesPerTenant` in vminsert, via an enterprise or proxy layer) |
| B4 | Hot tenant (noisy neighbour) | One tenant dominates RPS or ingest | Per-tenant rate limits (authz, Loki, Tempo, gateway), quotas | Dedicated node pool or namespace (silo tier) |
| B5 | NAT throughput or cost | NAT bytes rising | VPC endpoints for AWS APIs | Egress via Network Firewall in the shared inspection VPC |
| B6 | ALB connection limits for SSE chat | 5xx on long streams | Idle timeout 300 s, `least_outstanding_requests` | Dedicated ALB for chat if needed |

## 5. Load-testing strategy

1. **Baseline** (`normal-load.js`, 30 min) on every release to staging: regression gate on p95 and error rate.
2. **Peak** (`peak-5x.js`) weekly and before onboarding big tenants. It validates HPA targets and Karpenter limits.
3. **Spike** (`spike-10x.js`) monthly via k6-operator. It validates the warm buffer, KEDA reaction time and WAF.
4. **Bottleneck discovery** (`db-bottleneck.js`) per quarter or after schema changes. It records the saturation point.
5. **Resilience** (`redis-failure.js`, `ai-provider-failure.js`, `az-failure.js` with FIS) quarterly in staging, plus yearly prod game days.
6. Results feed back into `values-prod.yaml` (requests, min/max) and this document. A unit capacity marked "to verify" counts as validated only after a recorded k6 run.
