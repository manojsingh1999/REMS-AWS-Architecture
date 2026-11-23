# REMS Security Implementation

Architecture and diagrams are in [`architecture/07-security.md`](../architecture/07-security.md). This folder holds the enforceable artefacts.

| Control (PDF requirement) | Artefact | Enforced by |
|---|---|---|
| IAM least privilege | `iam/permission-boundary-workload.json`, per-service Pod Identity policies (`terraform/modules/rems-environment/identities.tf`). Services without AWS needs get **no role** | IAM boundary + SCP |
| Account guardrails | `iam/scp/*.json` (7 SCPs) | AWS Organizations |
| CI/CD credentials | GitHub OIDC roles (`terraform/modules/github-oidc`) pinned to repo + environment, `iam/permission-boundary-terraform.json` | STS trust policy |
| RBAC (product) | `opa/tenant_isolation.rego` (roles → actions per resource type) | Authorization Service |
| RBAC (Kubernetes) | `kubernetes/base/rbac.yaml`, EKS access entries, ArgoCD AppProject roles | kube-apiserver |
| Tenant isolation | JWT claim → OPA → Postgres RLS (`database/sql/03-row-level-security.sql`) → telemetry tenant headers → S3 prefixes | 5 independent layers |
| Secrets management | Secrets Manager (KMS, replicated to DR) → External Secrets → K8s Secret (KMS envelope) mounted as files | ESO + IAM |
| KMS | 9 CMKs per environment with rotation (`terraform/modules/kms`) | KMS key policies |
| Network policies | `kubernetes/base/network-policies.yaml` (default deny) + per-chart allow-lists | VPC CNI policy agent |
| WAF | `terraform/modules/waf` (IP reputation, OWASP common, SQLi, Linux, rate limits, log redaction) | AWS WAF on ALB |
| CloudTrail | Organization trail, log file validation, S3 Object Lock (compliance, 1 y), CloudWatch copy | `terraform/landing-zone/security.tf` |
| GuardDuty | Org-wide, EKS audit logs, runtime monitoring (managed agent), RDS login, S3, malware | `terraform/modules/security-baseline` |
| Security Hub | FSBP + CIS 3.0, cross-region aggregation, HIGH/CRITICAL → SNS | `terraform/modules/security-baseline` |
| Container image scanning | Trivy (CI gate), ECR enhanced scanning (Inspector, continuous), nightly re-scan, cosign signatures verified by Kyverno | `.github/workflows`, `kyverno/policies.yaml` |
| MCP authorization & audit | `opa/mcp_tools.rego` (allow-list, read-only, tenant scope, limits, rate), read-only RBAC, no IAM role, deny-exec policy, audit pipeline | Authorization Service + Kyverno + IAM |

## Validation

```bash
opa test security/opa -v                       # 12 policy unit tests (tenant isolation + MCP)
kubeconform -strict -summary security/kyverno  # Kyverno CRD schema
kyverno apply security/kyverno/policies.yaml --resource rendered/prod/   # in CI, needs registry access for verifyImages
```

## Documents

* [threat-model.md](threat-model.md): STRIDE analysis of the REMS platform.
* [audit-logging.md](audit-logging.md): what gets logged, where, retention, tamper resistance.
* [secrets-rotation.md](secrets-rotation.md): rotation procedures for DB, Redis and LLM provider keys.
