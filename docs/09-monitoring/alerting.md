# Alerting

**Status:** ✅ PrometheusRules (`monitoring/rules/*.yaml`, 114 rules, promtool-clean), Alertmanager routing (`kube-prometheus-stack/values.yaml`), CloudWatch alarms + SNS + Budgets (`terraform/modules/monitoring`). 🟡 SNS topic ARN in Alertmanager is a placeholder, and the PagerDuty endpoint is optional (`pagerduty_endpoint`). ⚠️ Not deployed.

## Two independent paths

| Path | Covers | Survives cluster outage? |
|---|---|---|
| Prometheus → Alertmanager → SNS (critical) / Slack (warning) | SLO burn rates, pods, autoscaling, rollouts, AI gateway, telemetry cost | No |
| CloudWatch alarms → SNS | EKS, Aurora (connections, replica lag, Global DB lag), Valkey (CPU, memory), ALB 5xx, audit deny bursts, budgets, cost anomalies | **Yes** |

## Alert catalogue

| Rule file | Alerts |
|---|---|
| `platform-alerts.yaml` | RemsAvailabilityZoneDegraded, RemsPodCrashLooping, RemsAutoscalerAtMax, RemsRolloutAborted, RemsPendingPodsTooLong, RemsKarpenterNodePoolNearLimit, RemsPVCAlmostFull, RemsExternalSecretSyncFailing |
| `ai-alerts.yaml` | RemsLLMProviderErrors, RemsLLMAllProvidersDown, RemsTenantLLMBudgetNearlyExhausted, RemsMCPDeniedToolCalls |
| `slo-rules.yaml` | RemsSLOAvailabilityBurnRate, RemsSLOLatencyBurnRate (multi-window per service) + recording rules |
| `telemetry-cost-alerts.yaml` | RemsTenantLogVolumeSpike, RemsTenantIngestionRateLimited, RemsActiveSeriesGrowth |

Burn-rate policy (`monitoring/slo/slos.md`): 14.4× over 1 h/5 m and 6× over 6 h/30 m page. 3× over 1 d/2 h and 1× over 3 d/6 h open tickets.

## Steps

1. `terraform output` of the environment module gives `alerts_topic_arn` (🟡 not re-exported at the environment root, see [infrastructure deployment](../02-aws-infrastructure/infrastructure-deployment.md#outputs-to-copy-into-gitops-values)).
2. Set `topic_arn` and `region` in the Alertmanager `sns_configs` (`kube-prometheus-stack/values.yaml`). The Alertmanager service account has `sns:Publish` through `irsa_alertmanager`.
3. Confirm the SNS e-mail subscriptions (`alert_emails`). AWS sends a confirmation mail per address.
4. Optional: set `pagerduty_endpoint` in the monitoring module inputs.

## Verification

```bash
aws sns list-subscriptions-by-topic --topic-arn <alerts-topic-arn>
aws cloudwatch describe-alarms --alarm-name-prefix rems-prod --query 'MetricAlarms[].{n:AlarmName,s:StateValue}' --output table
# Fire a test alert through Alertmanager
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
amtool --alertmanager.url=http://localhost:9093 alert add RemsTestAlert severity=warning
```

The alarm name prefix depends on `name` in `module "monitoring"`. List all with `aws cloudwatch describe-alarms`.

## Every alert has a runbook

| Alert family | Runbook |
|---|---|
| SLO burn | `runbooks/slo-burn-rate.md` |
| AZ degraded | `runbooks/az-failure.md` |
| Autoscaler at max / traffic | `runbooks/traffic-spike.md` |
| Rollout aborted | `runbooks/bad-deployment-rollback.md` |
| LLM provider errors | `runbooks/ai-provider-outage.md` |
| MCP denied calls | `runbooks/compromised-mcp-tool.md` |
| Telemetry spikes | `runbooks/telemetry-cost-spike.md` |
| Aurora / Redis alarms | `runbooks/postgres-bottleneck.md`, `runbooks/redis-failure.md` |

## Rollback

Silence noisy alerts with an expiry (`amtool silence add ... --duration=2h --comment=INC-…`). Fix thresholds through PR.
