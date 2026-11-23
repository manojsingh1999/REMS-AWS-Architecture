# Application Testing

**Status:** 🟡 The platform provides the hooks. The tests themselves belong to the service repositories, which aren't available here.

## Hooks provided

| Stage | Hook | Where |
|---|---|---|
| Unit tests + coverage | `test-command` input of the reusable workflow (coverage uploaded as an artifact for Sonar) | `.github/workflows/app-build.yml` job `test` |
| Static analysis | SonarQube quality gate | job `quality` |
| Post-deploy smoke tests | `scripts/smoke-test.sh <base-url> [kube-context]` | manual / after promotion / after DR |
| Canary analysis | Error rate, p95 latency, restarts | `cicd/argo-rollouts/analysis-templates.yaml` |
| Load / resilience | k6 + FIS | [k6 load testing](k6-load-testing.md), [failure scenarios](failure-scenarios.md) |
| Tenant isolation | RLS SQL test, OPA unit tests | [tenant isolation](../07-security/tenant-isolation.md) |

## Smoke test (real script)

```bash
./scripts/smoke-test.sh https://app.staging.rems.example.com rems-staging
```

Checks: frontend responds over TLS 1.2+. API health route (`/api/healthz`, 🟡 placeholder P3) responds. Plain HTTP isn't served. No pending pods in `rems` and `rems-ai`. All pods ready. No degraded rollouts. ExternalSecrets synced. ArgoCD applications healthy. Exit code non-zero on any failure.

## Recommended per-service tests (📋 to implement in the service repos)

* Contract tests against the OpenAPI spec (rems-api, chat-engine).
* An integration test that runs with **two** tenant IDs and asserts no cross-tenant reads (DB and cache).
* An MCP test: every tool call without `mcp/tools.read`, or with a foreign `tenant_id`, is denied.
