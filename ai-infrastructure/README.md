# REMS AI Infrastructure (RCA · Chat · RAG · Embeddings · MCP)

Architecture and diagrams: [`architecture/08-ai-rag-mcp.md`](../architecture/08-ai-rag-mcp.md).

| Component | Implementation | Files |
|---|---|---|
| LLM integrations | **LLM gateway** (LiteLLM, OpenAI-compatible API) in `rems-ai`. Bedrock primary over a VPC endpoint, external providers as fallback | `llm-gateway/values.yaml`, `llm-gateway/k8s/` |
| Provider quotas | Per-deployment `rpm`/`tpm` + `usage-based-routing-v2`. Bedrock Service Quotas monitored (`InvocationThrottles` alarm) | `llm-gateway/values.yaml`, `terraform/modules/monitoring` |
| Request concurrency | `max_parallel_requests` per key, `global_max_parallel_requests` 1200. KEDA scales chat/RCA on in-flight requests | values, `helm/charts/{chat-engine,metadata-rca}` |
| Failover / rate limiting | Retries (2) → circuit breaker (`allowed_fails` 5, `cooldown_time` 60 s) → fallback model group → degraded non-LLM response | `llm-gateway/values.yaml`, `runbooks/ai-provider-outage.md` |
| Data protection | Bedrock (no training on inputs, in-region), Guardrails (PII anonymize, secrets block, prompt-attack filter), gateway message logging off, invocation logs KMS-encrypted, tenant opt-out of external providers | `terraform/modules/ai-platform` |
| Cost controls | Per-tenant team budgets and RPM/TPM, `max_tokens`, Redis response cache, model tiering (fast vs reasoning), Spot for embedding backfills, Cost Anomaly Detection | values, `rag/README.md` |
| RAG + embeddings | S3 documents (tenant prefixes, CRR+RTC) → chunk + redact → Titan Embeddings v2 (1024-d) → Aurora `rems-rag` pgvector HNSW with RLS | `rag/README.md`, `database/sql/04-pgvector-rag.sql` |
| AI-driven RCA | metadata-rca pulls alerts and incidents (REMS API), telemetry (MCP read tools), similar past RCAs/SOPs (RAG), then the reasoning model | `helm/charts/metadata-rca` |
| Chat Engine | Streams (SSE) through ALB `/chat` (idle timeout 300 s). Tools through MCP with the user's token | `helm/charts/chat-engine` |
| MCP Server | Internal ALB only, OAuth (Cognito `mcp/tools.read`), OPA tool policy, read-only RBAC, no IAM role, audit | `mcp/README.md`, `mcp/tool-catalog.yaml`, `security/opa/mcp_tools.rego` |

## Capacity model (100 tenants)

| Input | Assumption | Result |
|---|---|---|
| Chat sessions | 15 concurrent users/tenant at peak × 100 tenants × 10 % active | 150 concurrent sessions → ~300 in-flight LLM calls |
| RCA jobs | 50 M events/day → ~2 000 incidents/day → 1 RCA each, 4 LLM calls, ~6k tokens | ~48 M tokens/day ≈ 33k TPM average, 165k TPM at 5× peak |
| Embeddings | 20k new SOP/runbook chunks/day + incident summaries | < 30 M tokens/day, batched off-peak |
| Gateway sizing | 1 pod ≈ 100 concurrent streams | min 3 / max 12 replicas |

These numbers determine which Bedrock quota increases to request before onboarding (Claude Sonnet ≥ 400k TPM in-region, or cross-region inference profiles), and when Provisioned Throughput becomes cheaper (sustained > 60 % of the on-demand quota).
