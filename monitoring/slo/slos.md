# REMS Service Level Objectives

30-day rolling windows. The SLIs come from OpenTelemetry HTTP server metrics (`http_server_request_duration_seconds`). Alerting uses multi-window, multi-burn-rate rules (`monitoring/rules/slo-rules.yaml`).

| Service | Availability SLO (non-5xx) | Error budget / 30 d | Latency SLO | Pages on |
|---|---|---|---|---|
| rems-frontend | 99.95 % | 21.6 min | 99 % < 500 ms | 14.4× / 1 h, 6× / 6 h |
| rems-api | 99.95 % | 21.6 min | 99 % < 500 ms | 14.4× / 1 h, 6× / 6 h (availability and latency) |
| authorization-service | 99.95 % | 21.6 min | 99 % < 100 ms | 14.4× / 1 h, 6× / 6 h (availability and latency) |
| mcp-server | 99.9 % | 43.2 min | 99 % < 2.5 s | 14.4× / 1 h, 6× / 6 h |
| data-governance | 99.9 % | 43.2 min | 99 % < 5 s | 14.4× / 1 h, 6× / 6 h |
| chat-engine | 99.9 % | 43.2 min | 95 % < 10 s (streamed) | 14.4× / 1 h, 6× / 6 h |
| metadata-rca | 99.9 % | 43.2 min | 95 % < 30 s (async RCA) | 14.4× / 1 h, 6× / 6 h |

AI-backed services get 99.9 %. Their availability depends on third-party LLM providers, and when providers fail they degrade to non-LLM answers rather than returning errors (see `architecture/08-ai-rag-mcp.md`).

## Burn-rate policy

| Long / short window | Burn rate | Budget consumed | Severity | Action |
|---|---|---|---|---|
| 1 h / 5 m | 14.4× | 2 % in 1 h | critical (page) | Immediate response; consider rollback |
| 6 h / 30 m | 6× | 5 % in 6 h | critical (page) | Respond within 30 min |
| 1 d / 2 h | 3× | 10 % in 1 d | warning (ticket) | Next business day |
| 3 d / 6 h | 1× | 10 % in 3 d | warning (ticket) | Capacity or quality review |

## Error-budget policy

* **Budget > 50 %:** normal release cadence.
* **Budget 0–50 %:** canary steps are lengthened, and only one service at a time is promoted to prod.
* **Budget exhausted:** feature freeze for the service. Only reliability fixes ship until the 30-day budget recovers. Requires a postmortem.

## Out-of-band checks

These are independent of the in-cluster stack, in case Prometheus or Alertmanager fails.

* CloudWatch alarms (Terraform `modules/monitoring`): Aurora, Redis, EKS failed nodes, Bedrock throttling, authz-deny bursts, budgets and cost anomalies → SNS.
* Route 53 health checks on `https://app.<domain>/` drive the DNS failover record.
* The Alertmanager `Watchdog` alert acts as a dead man's switch towards the paging provider. If it stops arriving, the paging provider alerts on its absence.
