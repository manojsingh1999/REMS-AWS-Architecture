# Runbook: Compromised AI/MCP tool attempts an unauthorized infrastructure operation

**Alerts:** `RemsMCPDeniedToolCalls` (critical, category security), `rems-<env>-authz-deny-burst`, Kyverno policy violations (`rems-deny-exec-into-ai-pods`, `rems-mcp-readonly-guard`), GuardDuty EKS findings.

## Why the operation cannot succeed

| Attempt | Blocked by |
|---|---|
| Call a mutating tool (`delete_*`, `scale_*`, `exec`) | Not in `tool-catalog.yaml`, and OPA `mcp_tools.rego` rejects mutating verbs (severity critical) |
| Use the MCP pod's Kubernetes token to write | ClusterRole `rems-k8s-observer` allows get/list/watch only. Kyverno forbids new bindings for `mcp-server` |
| Call AWS APIs | No Pod Identity association, so no credentials. IMDS hop limit is 1. SCP denies mutating calls for AI roles |
| Reach other services or the internet | NetworkPolicy egress allow-list (authz, rems-api, observability read ports, kube-apiserver) |
| Exec into AI pods to pivot | Kyverno `rems-deny-exec-into-ai-pods` |
| Read other tenants' data | Tool calls execute with the end user's token and tenant |

## Respond

1. **Identify the source:** the audit log (`component=mcp-server decision=deny severity=critical`) gives subject, tenant, tool and `trace_id`. Then check the chat or agent session in Tempo.
2. **Contain:**
   * Revoke the user's or agent's tokens (Cognito `admin-user-global-sign-out`) and disable the MCP client app client if the client itself is compromised.
   * If prompt injection came from data (a log line or document), quarantine that document (S3 object tag `quarantine=true`, which RAG retrieval excludes).
   * Scale `mcp-server` to 0 if the server itself is suspected: `gh workflow run rollback.yml -R your-github-org/rems-microconfig ...`, or for break-glass `kubectl -n rems-ai scale rollout mcp-server --replicas=0` plus pausing ArgoCD for the app.
3. **Investigate:**
   * Compare CloudTrail and EKS audit logs for any **successful** write by `mcp-server` identities. The expected result is none.
   * Check GuardDuty runtime findings for the pod.
   * Review recent image and chart changes (cosign signature, SBOM diff).
4. **Eradicate and recover:** redeploy a known-good signed image, rotate any secrets the pod could read (it reads none by design), and restore the MCP service.
5. **Lessons:** add the injected pattern to Guardrails denied topics or regexes, and add an OPA test case.
