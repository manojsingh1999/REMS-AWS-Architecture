# MCP Security

**Status:** ✅ OPA tool policy (`security/opa/mcp_tools.rego`, tests in `policies_test.rego`), tool catalog (`ai-infrastructure/mcp/tool-catalog.yaml`), Kyverno guard, read-only RBAC, internal-only ALB, NetworkPolicy. 🟡 The MCP server implementation (the service that calls OPA and writes audit events) is application code outside this repository.

## Objective

AI agents and IDE clients can **read** observability data for their own tenant, and nothing else.

## Controls

| Control | Implementation |
|---|---|
| Exposure | Internal ALB only (`rems-internal`, `/mcp`), reachable from VPN/TGW |
| Authentication | Cognito MCP client (`cognito.mcp_client_id`), scope `mcp/tools.read` |
| Tool allow-list | 7 read-only tools: `query_metrics`, `query_logs`, `query_traces`, `get_incident`, `list_alerts`, `describe_workload`, `search_sops` |
| Forbidden verbs | `delete`, `apply`, `patch`, `exec`, `scale`, `restart`, `drain`, `create`, `update`, `put`, `write`, `terminate`, `rollback` can't appear in any tool name |
| Tenant scope | `input.tool.arguments.tenant_id == input.subject.tenant_id` and `token_tenant_verified` |
| Limits | Per-tool max time range and row limit. 60 calls/minute per subject |
| Kubernetes | `rems-k8s-observer` read-only ClusterRole. Kyverno `rems-mcp-readonly-guard` |
| AWS | No IAM role for mcp-server (no AWS credentials at all) |
| Audit | Every decision logged (schema: `security/audit-logging.md`) |

## Policy input example (from the header of `mcp_tools.rego`)

```json
{
  "subject": {"id": "...", "tenant_id": "t-1", "roles": ["sre"], "token_tenant_verified": true, "scopes": ["mcp/tools.read"]},
  "tool":    {"name": "query_logs", "arguments": {"tenant_id": "t-1", "time_range_minutes": 60, "limit": 500}},
  "rate":    {"calls_last_minute": 12}
}
```

## Steps: evaluate a decision locally

```bash
cat > /tmp/mcp-input.json <<'EOF'
{"subject":{"id":"u1","tenant_id":"t-1","roles":["sre"],"token_tenant_verified":true,"scopes":["mcp/tools.read"]},
 "tool":{"name":"query_logs","arguments":{"tenant_id":"t-2","time_range_minutes":60,"limit":500}},
 "rate":{"calls_last_minute":1}}
EOF
opa eval -d security/opa/mcp_tools.rego -i /tmp/mcp-input.json 'data.rems.mcp.allow'
```

Expected: `false` (cross-tenant). Change `t-2` to `t-1` and it becomes `true`.

## Incident response

`runbooks/compromised-mcp-tool.md`: revoke the client, scale mcp-server to 0, preserve audit logs, rotate tokens.

## Rollback

Policy changes go through PR + `opa test`. To disable MCP entirely: `kubectl scale rollout mcp-server -n rems-ai --replicas=0` and pause auto-sync.
