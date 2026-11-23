# Runbook: Customer attempts to access another tenant's incident or RCA records

**Alerts:** `rems-<env>-authz-deny-burst` (CloudWatch metric filter on `/rems/<env>/audit`), `RemsMCPDeniedToolCalls` with severity high. **Severity:** security incident (SEV-2), owned by the security on-call.

## Why it fails safely (5 layers)

1. `tenant_id` comes only from the signed Cognito JWT. Body, query and path tenant parameters are ignored.
2. OPA `rems.authz`: the resource tenant must equal the subject tenant. If not, the request is denied and audited with the reason `cross-tenant access denied`.
3. Postgres RLS (`FORCE`): even a buggy query returns **0 rows** for other tenants, and the composite FK blocks cross-tenant references.
4. Telemetry: Loki, Tempo and VictoriaMetrics tenant headers are set server-side from the token.
5. S3 and RAG: tenant prefixes, plus a tenant filter on vector search, plus RLS.

## Investigate

```bash
# CloudWatch Logs Insights on /rems/prod/audit
fields ts, tenant_id, subject, component, event, reasons.0, source_ip
| filter decision = "deny" and reasons.0 like /cross-tenant/
| stats count(*) as attempts by subject, tenant_id, source_ip
| sort attempts desc
```

* A single user with a few attempts usually means a bookmarked link or a UI bug. Look at the referrer and the `trace_id` in Tempo.
* Many object IDs enumerated, or automation patterns, mean a malicious probe.
* Any **allow** decision where the resource tenant differs from the subject tenant is a **SEV-1** potential breach. Stop and escalate.

## Contain (malicious)

1. Disable the user in Cognito (`admin-disable-user`) and revoke refresh tokens (`admin-user-global-sign-out`).
2. Add a WAF IP set block for the source IPs (time-boxed).
3. Notify the attacker's tenant admin (it's their account) and the targeted tenant per contract.
4. Preserve evidence: export the audit logs (they are already in Object Lock in Log Archive) and the ALB/WAF logs.

## Verify the controls (quarterly)

Run the OPA tests (`opa test security/opa`), the RLS verification block in `database/sql/03-row-level-security.sql`, and an automated cross-tenant DAST test in staging using two synthetic tenants.
