# REMS Threat Model (STRIDE)

Scope: the internet-facing REMS platform, tenant data (incidents, RCA, SOP documents, telemetry), AI components (chat, RCA, MCP) and the delivery pipeline.

| # | Threat | STRIDE | Attack path | Mitigations | Residual risk / detection |
|---|---|---|---|---|---|
| T1 | Tenant A reads tenant B's incidents/RCA | Information disclosure | IDOR on `/api/...?tenant=` or a missing WHERE clause | tenant from the signed JWT only. OPA same-tenant rule. Postgres RLS with `FORCE`. Per-tenant telemetry org IDs | Authz deny-burst alarm, GuardDuty. RLS integration tests in CI |
| T2 | Prompt injection makes the AI exfiltrate other tenants' data | Info disclosure / EoP | Malicious log line or SOP content instructs the model to call tools | Tools are authorized with the *user's* token and tenant scope, not the model's. Read-only allow-list. Guardrails prompt-attack filter. Retrieval filtered by tenant before ranking | MCP audit (`severity=high/critical`) → SNS |
| T3 | Compromised MCP tool or agent attempts an infra change | Elevation of privilege | Tool calls `kubectl delete` or AWS write APIs | No mutating tools exist. OPA forbids mutating verbs. K8s RBAC is read-only. No IAM role (no AWS creds at all). SCP denies writes for AI roles. Kyverno blocks exec and RBAC changes. NetworkPolicy egress allow-list | Kyverno and API-server audit, GuardDuty EKS |
| T4 | Stolen developer or CI credentials | Spoofing | Leaked access key or PAT | No IAM users or keys (SCP). OIDC trust is pinned to repo + environment. Identity Center MFA. Short sessions. Gitleaks | CloudTrail Insights, GuardDuty anomalous behaviour |
| T5 | Malicious or vulnerable image deployed | Tampering | Dependency CVE, typosquat, registry poisoning | Trivy gates, SBOM, cosign keyless signing, Kyverno `verifyImages` + registry allow-list, immutable ECR tags, Inspector continuous scan | Nightly re-scan, Security Hub |
| T6 | Credential stuffing or DDoS on the login and API | DoS / Spoofing | Bot traffic | WAF rate limits (per IP, stricter on auth), IP reputation, Cognito threat protection, autoscaling, Shield Standard | WAF metrics, ALB 5xx alarms |
| T7 | Lateral movement from a compromised pod | EoP | RCE in a dependency | Non-root, read-only FS, no capabilities, seccomp, default-deny netpol, IMDS blocked (hop limit 1), per-pod IAM, no service links | GuardDuty runtime monitoring |
| T8 | Data store exposure | Info disclosure | Public snapshot, open SG | Private data subnets with no route, SCP denies public RDS/unencrypted storage, KMS CMKs, Access Analyzer, Config rules | Security Hub controls |
| T9 | Log/audit tampering to hide activity | Repudiation | Delete trails or log groups | SCP protects CloudTrail/GuardDuty/flow logs. Log Archive account with S3 Object Lock (compliance). Log file validation | CloudTrail digest validation |
| T10 | Data Governance scanner abused to pivot into customer networks | EoP | Scanner reaches arbitrary hosts | Egress only to declared customer CIDRs via TGW, per-tenant credentials in Secrets Manager, read-only DB users recommended to customers | Flow logs, Network Firewall logs |
| T11 | Runaway AI cost (abuse or bug) | DoS (financial) | Loop calling the LLM | Per-tenant budgets/RPM in the LLM gateway, `max_tokens` caps, Cost Anomaly Detection | Budget alerts at 80/100 % |
