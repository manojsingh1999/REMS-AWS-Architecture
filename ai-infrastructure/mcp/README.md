# MCP Server: Secure Tooling for REMS Observability Data

## Exposure and authentication

* Streamable HTTP MCP transport, served **only** on the internal ALB (`mcp.<env>.rems.example.com`), reached over VPN or a customer PrivateLink endpoint service.
* OAuth 2.1 bearer tokens from Cognito: app client `mcp`, scope `mcp/tools.read`, 15-minute access tokens, with the `tenant_id` claim injected at login.
* The server validates the JWT (issuer, audience, expiry, signature via cached JWKS) before parsing any MCP message.

## Authorization per tool call

1. Look up the tool in the allow-list `tool-catalog.yaml`. An unknown tool is denied.
2. Evaluate OPA `data.rems.mcp.decision` (`security/opa/mcp_tools.rego`): scope, read-only verb check, tenant scope equals the token tenant, role, argument limits, and rate.
3. Execute with the **caller's** token against REMS API or the observability read endpoints, with the tenant header from the token. MCP never uses a shared service identity for data access.
4. Write an audit event (`security/audit-logging.md`) for both allow and deny decisions.

## Hard limits that hold even if the policy layer is bypassed

| Layer | Limit |
|---|---|
| Kubernetes RBAC | `rems-k8s-observer`: get/list/watch only, no secrets, no exec |
| Kyverno | `rems-mcp-readonly-guard` (no other bindings), `rems-deny-exec-into-ai-pods` |
| AWS IAM | No Pod Identity association, so no AWS credentials at all. SCP denies mutating actions for `rems-*-mcp-*` roles |
| Network | Egress only to authorization-service, rems-api, observability read ports and the kube-apiserver |
| Runtime | Non-root, read-only root FS, no capabilities, seccomp |
| Detection | `RemsMCPDeniedToolCalls` (Prometheus) and `authz-deny-burst` (CloudWatch) page security |

Response: `runbooks/compromised-mcp-tool.md`.
