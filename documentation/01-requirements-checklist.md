# REMS – Requirements Traceability Checklist

Source: *Cloud Infrastructure Architecture Design Challenge — REMS* (PDF, 4 pages).
Every requirement in the PDF is listed below with the artefact that satisfies it.
Status legend: ✅ implemented in this repo · 🟡 implemented with placeholder values (see `02-assumptions.md`) · 📄 design/documentation only (by nature).

## A. Applications in scope (PDF "Technical Scope")

| # | PDF requirement | Implementation | Status |
|---|---|---|---|
| A1 | Frontend – React/Vite (dashboards, alerts, incidents, admin) | `helm/charts/rems-frontend`, served via ALB + WAF, static assets cache headers | 🟡 |
| A2 | REMS API – FastAPI + PostgreSQL, Prometheus/VictoriaMetrics, Loki, Tempo, Kubernetes | `helm/charts/rems-api` (API + optional background worker), read-only K8s RBAC, NetworkPolicy egress to Aurora/VM/Loki/Tempo | 🟡 |
| A3 | Authorization Service – RBAC, tenant permissions, policy enforcement, audit logging | `helm/charts/authorization-service`, `security/opa/*.rego`, audit log pipeline (`security/audit-logging.md`) | 🟡 |
| A4 | Data Governance – DB scanning, policies, PostgreSQL/MySQL integrations | `helm/charts/data-governance`, egress controlled by NetworkPolicy + VPC endpoint/PrivateLink pattern for customer DBs | 🟡 |
| A5 | Metadata RCA / Savvy – RCA, SOPs, RAG, documents, pgvector, LLM | `helm/charts/metadata-rca`, dedicated Aurora cluster `rems-rag` with pgvector, S3 documents bucket, Bedrock/LLM gateway | 🟡 |
| A6 | New Chat Engine – AI incident/alert/infra/log/trace analysis | `helm/charts/chat-engine`, KEDA concurrency scaling, LLM gateway | 🟡 |
| A7 | MCP Server – secure tools for querying observability data | `helm/charts/mcp-server`, internal-only ingress, OPA tool policy, read-only identity, audit | 🟡 |
| A8 | Supporting infra – PostgreSQL, Redis, object storage, IdP, observability backends, secrets, external AI providers | Terraform `aurora-postgresql`, `elasticache-redis`, `s3-bucket`, `cognito`, `kms`, `ai-platform`; `monitoring/` (VictoriaMetrics, Loki, Tempo); External Secrets + Secrets Manager | ✅ |
| A9 | Helm deployments, CI/CD automation, load testing | `helm/`, `.github/workflows/`, `cicd/argocd`, `load-testing/` | ✅ |

## B. Architecture requirements

| # | Requirement | Implementation | Status |
|---|---|---|---|
| B1 | Multi-account landing zone | `terraform/landing-zone` (Organizations, OUs, accounts, SCPs, delegated admins) | ✅ |
| B2 | Networking, VPC segmentation, private subnets | `terraform/modules/vpc` – 3 AZ × {public, private-app, private-data, intra} subnets, NAT per AZ, flow logs, endpoints | ✅ |
| B3 | Secure connectivity | Transit Gateway (network account), VPC endpoints (PrivateLink), no public nodes, SSM instead of SSH, EKS private endpoint | ✅ |
| B4 | IAM boundaries | SCPs, permission boundary `security/iam/permission-boundary.json`, EKS Pod Identity per service | ✅ |
| B5 | Centralised security services | `terraform/modules/security-baseline` – Org CloudTrail, GuardDuty (EKS/RDS/S3/Runtime), Security Hub, Config, Access Analyzer, Inspector | ✅ |
| B6 | Multi-AZ EKS, independent scaling of components | `terraform/modules/eks` + Karpenter, per-service HPA/KEDA | ✅ |
| B7 | Compute provisioning, pod scheduling, autoscaling, ingress, service discovery, zero-downtime deploy | `architecture/04-eks-platform.md`, Karpenter NodePools, topology spread, PDBs, ALB controller, CoreDNS, Argo Rollouts canary | ✅ |
| B8 | HA PostgreSQL, Redis, object storage, observability data | Aurora PG Multi-AZ + Global DB, ElastiCache Multi-AZ cluster mode, S3 versioning + CRR/RTC, Loki/Tempo on S3 | ✅ |
| B9 | Connection pooling, retention, encryption, replication, backups, restore | RDS Proxy, Aurora backups 35 d + PITR, AWS Backup vault lock, `database/` restore scripts & runbooks | ✅ |
| B10 | AuthN, AuthZ, tenant isolation, secrets, workload identity, netpols, image scanning, central audit | Cognito/OIDC, Authorization Service + OPA, Postgres RLS, Loki/Tempo/VM tenant headers, Secrets Manager + ESO, Pod Identity, Calico-free VPC CNI netpols, ECR + Trivy + Inspector, CloudTrail + audit pipeline | ✅ |
| B11 | Terraform, registries, Helm, GitOps; testing, security gates, progressive delivery, rollback | GitHub Actions (OIDC), ECR, Helm, ArgoCD ApplicationSets, Argo Rollouts with Prometheus analysis | ✅ |
| B12 | End-to-end self-monitoring: metrics, logs, traces, SLOs, alerts, dependency mapping, infra health | `monitoring/` kube-prometheus-stack, Loki, Tempo (service graph), OTel Collector, SLO burn-rate rules, CloudWatch out-of-band alarms | ✅ |
| B13 | AI: RCA, chat, RAG, embeddings, MCP – secure & scaled; quotas, concurrency, data protection, cost controls | `ai-infrastructure/` LLM gateway (LiteLLM) with per-tenant budgets/RPM, Bedrock VPC endpoint + Guardrails, KEDA concurrency, circuit breakers | ✅ |
| B14 | 99.95 % availability, auto recovery from single-AZ failure | 3-AZ everything, N+1 sizing, PDBs, Aurora/Redis automatic failover, FIS AZ experiment | ✅ |
| B15 | RPO 15 min / RTO 2 h for critical services | Aurora Global DB (RPO ≈ seconds), S3 RTC (15 min SLA), warm-standby EKS in DR region, `runbooks/dr-regional-failover.md` | ✅ |

## C. Scaling assumptions (PDF) and how they are used

| Input | Value | Where used |
|---|---|---|
| Initial tenants | 20 | `documentation/05-capacity-plan.md` |
| Target tenants | 100+ | capacity plan, Aurora/Redis sizing, cost model |
| Daily operational events | 50 M (≈ 579 ev/s avg) | capacity plan, k6 `normal-load` |
| Peak | 5 × avg (≈ 2 894 ev/s) | k6 `peak-5x` |
| Review scenario spike | 10 × in 5 min (≈ 5 787 ev/s) | k6 `spike-10x`, KEDA/Karpenter tuning |
| Telemetry retention | 30–90 days | Loki/Tempo/VM retention + S3 lifecycle |
| Environments | Dev, Staging, Prod | `terraform/environments/{dev,staging,prod,prod-dr}`, Helm `values-<env>.yaml` |

## D. Expected deliverables (PDF)

| # | Deliverable | Location |
|---|---|---|
| D1 | Architecture diagram | `architecture/*.md` (Mermaid) |
| D2 | Application deployment matrix | `documentation/03-application-deployment-matrix.md` |
| D3 | Security architecture | `architecture/07-security.md`, `security/` |
| D4 | CI/CD architecture | `architecture/10-cicd.md`, `.github/workflows/`, `cicd/` |
| D5 | Scalability plan | `documentation/05-capacity-plan.md`, `load-testing/` |
| D6 | HA/DR strategy | `architecture/09-ha-dr.md`, `runbooks/` |
| D7 | Cost model | `documentation/06-cost-model.md` |
| D8 | Implementation roadmap | `documentation/07-implementation-roadmap.md` |

## E. Architecture review scenarios (PDF)

| Scenario | Answer / runbook |
|---|---|
| One AZ unavailable | `runbooks/az-failure.md`, FIS `load-testing/chaos/fis-az-power-interruption.json`, k6 `az-failure.js` |
| API traffic 10× in 5 min | `runbooks/traffic-spike.md`, k6 `spike-10x.js` |
| PostgreSQL is the bottleneck | `runbooks/postgres-bottleneck.md`, k6 `db-bottleneck.js` |
| AI provider unavailable / rate limiting | `runbooks/ai-provider-outage.md`, LLM gateway fallbacks, k6 `ai-provider-failure.js` |
| Cross-tenant access attempt | `runbooks/cross-tenant-access-attempt.md`, `database/sql/03-row-level-security.sql`, `security/opa/tenant_isolation.rego` |
| Regression from a deployment | `runbooks/bad-deployment-rollback.md`, Argo Rollouts AnalysisTemplates |
| Compromised AI/MCP tool attempts infra operation | `runbooks/compromised-mcp-tool.md`, `security/opa/mcp_tools.rego`, Kyverno + RBAC + SCP |
| Telemetry volume makes costs spike | `runbooks/telemetry-cost-spike.md`, per-tenant ingestion limits, cost alarms |
