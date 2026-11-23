# Cost Optimization

**Status:** ✅ Architectural levers implemented (Graviton, Spot pools, consolidation, I/O-Optimized, lifecycle tiering, per-tenant LLM budgets). 📋 Commitment purchases (Savings Plans, RIs) are recommendations only. They're financial decisions for the account owner after 1–2 months of real usage data.

## Levers modelled in `scripts/cost_model.py` (`OPT` list)

| Lever | Applies to | Modelled saving |
|---|---|---|
| Compute Savings Plan 1y no-upfront | EC2 system, ai, observability | 27 % |
| Savings Plan on the on-demand floor | EC2 general | 15 % |
| Aurora Reserved Instances 1y (r7g) | Aurora core, rag, DR secondaries | 30 % |
| ElastiCache reserved nodes 1y | Valkey | 30 % |
| More Haiku routing + semantic cache + prompt trimming | Bedrock LLM | 25 % |
| Drop unused endpoints (ssm / ec2messages) in prod | VPC endpoints | 40 % |
| Dev: 5 essential endpoints only | dev NAT + endpoints | 35 % |

Overall: 26,576 → 20,588 USD/month (−23 %).

## Implemented in code

| Lever | Where |
|---|---|
| Graviton allowed in every NodePool (arm64-only for observability), multi-arch images | `kubernetes/base/karpenter.yaml`, `app-build.yml` `platforms` |
| Spot for workers (and general in dev) | NodePools, dev overlay |
| Consolidation (`WhenEmptyOrUnderutilized`) | NodePool `disruption` |
| Aurora Serverless v2 in dev, I/O-Optimized in prod | `terraform/environments/*/main.tf` |
| Single NAT in dev | `single_nat_gateway = true` |
| S3 lifecycle: documents → STANDARD_IA at 30 d → GLACIER_IR at 180 d; telemetry → STANDARD_IA at 30 d, expiry = `telemetry_retention_days` | `rems-environment/storage.tf` |
| Telemetry limits per tenant (Loki/Tempo/VM) | `monitoring/*/values.yaml` |
| LLM budgets, caching, model tiering | `ai-infrastructure/llm-gateway/values.yaml` |
| DR warm standby at minimal size until promoted | `dr_promoted`, `values-prod-dr.yaml` |

## Further options (not implemented)

* Schedule dev/staging scale-down outside business hours (Karpenter NodePool limits = 0 via a CronJob, or KEDA cron scalers).
* Bedrock Provisioned Throughput once sustained usage is above ~60 % of the on-demand quota.
* Review `interface_endpoints` per environment (see [VPC endpoints](../02-aws-infrastructure/vpc-endpoints.md)).

## Monitoring cost

* AWS Budgets + Cost Anomaly Detection (`modules/monitoring`).
* `RemsTenantLogVolumeSpike`, `RemsActiveSeriesGrowth`, `RemsTenantLLMBudgetNearlyExhausted` alerts.
* Tag-based Cost Explorer reports (`Project`, `Environment` tags enforced by the tag policy).
