# Runbook: AI provider unavailable or rate-limiting

**Alerts:** `RemsLLMProviderErrors` (warning), `RemsLLMAllProvidersDown` (critical), `rems-<env>-bedrock-throttles` (CloudWatch), `RemsTenantLLMBudgetNearlyExhausted`.

## Automatic behaviour (LLM gateway)

1. Retries, at most 2, with backoff on 429 and 5xx.
2. A **circuit breaker** takes a deployment out of rotation for 60 s after 5 failures.
3. **Fallback chain:** `rems-reasoning` (Bedrock Claude Sonnet) → `rems-reasoning-fallback` (external Anthropic API), and `rems-fast` (Bedrock Haiku) → `rems-fast-fallback` (OpenAI). Tenants with `allow_external_llm=false` are pinned to Bedrock and skip external fallbacks.
4. If every model fails, chat returns tool results with a **degraded** deterministic summary (header `X-Rems-Degraded: true`), and RCA jobs stay queued and retry with exponential backoff for up to 6 h.
5. The core REMS API is unaffected. AI calls are isolated in `rems-ai`, with separate node pool, quotas and timeouts.

## Diagnose

* Grafana `REMS / AI gateway`: failures by provider, fallbacks, latency.
* Bedrock: `aws cloudwatch get-metric-statistics --namespace AWS/Bedrock --metric-name InvocationThrottles ...`, plus the AWS Health Dashboard for Bedrock in the region.
* External provider status pages.
* Throttling (429) vs outage (5xx or timeouts) vs a guardrail block (400 with the guardrail message).

## Actions

| Cause | Action |
|---|---|
| Bedrock throttling (quota) | Request a Service Quotas increase for the model's TPM/RPM. Enable the cross-region inference profile (`apac.*`) in the gateway model list. Lower `rpm` for batch callers (embedding backfills) |
| Regional Bedrock outage | Fallback handles it. If the outage runs long, switch `rems-reasoning` to an inference profile in another region (data-residency check with the product owner) |
| External fallback also failing | Accept degraded mode and post a status page update. Do not disable the circuit breaker |
| One tenant exhausting quota | Lower the team `rpm_limit`/`tpm_limit` via the gateway admin API and notify the account owner |
| Budget exhausted | Expected hard stop. Raise `max_budget` only with commercial approval |

## Validate

`load-testing/chaos/run-chaos.sh ai-provider` with k6 `ai-provider-failure.js`.
