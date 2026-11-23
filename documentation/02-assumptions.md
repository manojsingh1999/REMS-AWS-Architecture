# Assumptions & Missing-Information Register

The PDF says to use the existing Dockerfiles, Helm charts and deployment configs as references, but none were supplied with it.
So this repository **does not invent application behaviour**. Any value that would normally come from the application source is
a clearly marked `PLACEHOLDER` and is listed here. To find them all, run:

```bash
grep -rn "PLACEHOLDER" --include=*.yaml --include=*.tf --include=*.tfvars --include=*.js --include=*.json .
```

## 1. Application-level placeholders (replace from the service repos)

| ID | Item | Placeholder used | Where | How to resolve |
|---|---|---|---|---|
| P1 | Container port – frontend | `8080` (nginx-unprivileged convention) | `helm/charts/rems-frontend/values.yaml` | `EXPOSE` in frontend Dockerfile |
| P2 | Container port – Python services | `8000` (uvicorn convention) | `helm/charts/*/values.yaml` | `EXPOSE` / uvicorn `--port` in each Dockerfile |
| P3 | Liveness / readiness paths | `/healthz`, `/readyz` | all service `values.yaml` | FastAPI health routes |
| P4 | Prometheus metrics path | `/metrics` | `serviceMonitor.path` | instrumentator config |
| P5 | Background worker command | `["PLACEHOLDER-worker-entrypoint"]` (worker disabled by default) | `helm/charts/rems-api/values.yaml` | Celery/RQ/Arq entrypoint, if one exists |
| P6 | App-specific env vars | none are invented. Secrets come in as keys of a Secrets Manager JSON document (`envFrom`), and config goes in `extraEnv` | `values.yaml` → `extraEnv`, Secrets Manager | Settings classes in each service |
| P7 | API paths for load tests | `load-testing/config/endpoints.example.json` | k6 | OpenAPI spec of REMS API / Chat Engine |
| P8 | Image names | `<shared-services-account>.dkr.ecr.<region>.amazonaws.com/rems/<service>` (repos created by this Terraform) | ECR module, Helm `image.repository` | – (our design) |
| P9 | AWS account IDs, domain, GitHub org | `111111111111`-style IDs, `rems.example.com`, `your-github-org` | `*.tfvars`, ArgoCD apps | Real org values |

Standard, vendor-defined variables are used without placeholders because they're not application-specific:
`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_TRACES_SAMPLER(_ARG)`, `AWS_REGION`.

## 2. Architectural assumptions

| # | Assumption | Rationale |
|---|---|---|
| A1 | Primary region **ap-south-1 (Mumbai)**, DR region **ap-southeast-1 (Singapore)** | Low latency for an India-based team. Singapore has the full service set (Bedrock, Aurora Global DB, EKS). Both are Terraform variables. |
| A2 | Multi-tenant **pooled** model (shared clusters and DBs) with logical isolation. Optional **silo** tier (dedicated Aurora cluster or namespace) for regulated tenants | Cost efficient for 20→100 tenants. Isolation is enforced in 5 layers (see `architecture/07-security.md`) |
| A3 | Every request carries a tenant ID claim (`tenant_id`) in the OIDC JWT, issued by Cognito (federating to the customer IdP via SAML/OIDC) | Needed for tenant isolation in authz, DB RLS and telemetry backends |
| A4 | Average operational event ≈ 1 KB. 50 M/day ≈ 50 GB/day raw, ≈ 6 GB/day compressed in object storage | Drives storage and cost sizing |
| A5 | User-facing API traffic: ≈ 150 req/s average and ≈ 750 req/s peak at 100 tenants. Each API pod sustains ≈ 100 req/s at p95 < 300 ms (to validate with k6) | Sets HPA minimums. **Must be re-baselined with k6** |
| A6 | Container images are built multi-arch (`linux/amd64,linux/arm64`) so workloads can run on Graviton | ≈ 20 % lower compute cost. Karpenter falls back to amd64 if needed |
| A7 | Amazon Bedrock is the primary LLM/embedding provider (in-region, private VPC endpoint, no training on customer data). External providers (OpenAI/Anthropic API) are fallback via an LLM gateway and an egress allowlist | Data residency, quota control, provider failover |
| A8 | REMS's tenant telemetry (product data) is stored in a multi-tenant **VictoriaMetrics cluster + Loki + Tempo** on EKS backed by S3. The platform's own monitoring uses a separate tenant (`rems-platform`), plus an independent CloudWatch out-of-band path | PDF lists Prometheus/VictoriaMetrics, Loki and Tempo as integrations |
| A9 | Critical services for DR (RPO 15 m / RTO 2 h): Frontend, REMS API, Authorization, Metadata RCA, Chat Engine, MCP, Aurora, S3 documents. Telemetry stores are *important, not critical* (RPO 24 h, rebuildable) | Replicating 90 days of telemetry cross-region would be the largest cost item with little business value |
| A10 | Redis holds cache, sessions, rate-limit counters and transient queues only. It is never the system of record | So Redis loss means degradation, not data loss |
| A11 | Data Governance reaches customer PostgreSQL/MySQL through customer-provided PrivateLink endpoint services or Site-to-Site VPN attached to the Transit Gateway. Credentials are stored per tenant in Secrets Manager | Public DB scanning over the internet isn't acceptable |
| A12 | GitOps repo = this repo (`helm/` + `cicd/argocd`). App source code lives in separate repos that call the reusable workflow `.github/workflows/app-build.yml` | Clean split between app CI and platform CD |
| A13 | Kubernetes 1.31, Terraform ≥ 1.10 (S3-native state locking, no DynamoDB), AWS provider ~> 5.80, Helm 3.16, ArgoCD 2.13, Argo Rollouts 1.7, Karpenter 1.1, KEDA 2.16, Kyverno 1.13 | Current stable at time of writing. Pin and upgrade through PRs |
| A14 | Services emit OpenTelemetry HTTP semantic-convention metrics (`http_server_request_duration_seconds`, `http_server_active_requests`, label `service_name`) | Used by KEDA triggers, canary analysis and SLO rules. If a service uses `prometheus-fastapi-instrumentator` instead, change the metric names in `cicd/argo-rollouts` and `monitoring/rules` |
| A15 | The LLM gateway is LiteLLM (OSS), deployed from its Helm chart | Provider abstraction, budgets, fallbacks and metrics out of the box. Key names must be verified against the pinned chart version |
| A16 | Bedrock model IDs in tfvars are on-demand IDs. In ap-south-1 some Claude models are only offered through cross-region (APAC) inference profiles | Use profile ARNs in `allowed_model_ids` and the gateway model list where needed |
| A17 | Audit events from the authorization service and the MCP server are emitted as OTel logs with the attribute `event.domain=audit` (PLACEHOLDER contract) | The OTel `logs/audit` pipeline routes them to CloudWatch |

## 3. Open questions for the product team

1. Actual ports, health routes and env var names for each service (P1–P6).
2. Does Chat Engine use WebSockets or SSE? This repo assumes HTTP streaming (SSE). ALB idle timeout is set to 300 s.
3. Is background processing a separate process (worker) or in-process? The chart supports both.
4. Tenant data-residency requirements (single region versus per-region tenant pinning).
5. Approved LLM providers and models per tenant, and whether any tenant forbids external providers.
