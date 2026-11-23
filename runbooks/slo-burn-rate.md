# Runbook: SLO error-budget burn

**Alerts:** `RemsSLOAvailabilityBurnRate`, `RemsSLOLatencyBurnRate` (labels: `service`, `window`, `severity`).

1. **Scope.** Open `REMS / SLO overview`. Check whether one service is affected or several. Several services at once points to a shared dependency: Aurora, Redis, an AZ, or authz.
2. **Correlate with change.** Was there an ArgoCD sync in the last hour (`#rems-deployments`)? If yes, see [bad-deployment-rollback.md](bad-deployment-rollback.md), because rollback is the fastest mitigation.
3. **Locate.** Open `REMS / Service RED` for the service and look at errors by route, then latency by route. Jump to exemplar traces in Tempo, then to logs via the trace ID.
4. **Dependencies.** Use the Tempo service graph to see which edge turned red, then the matching runbook:
   * Postgres: [postgres-bottleneck.md](postgres-bottleneck.md)
   * Redis: [redis-failure.md](redis-failure.md)
   * LLM: [ai-provider-outage.md](ai-provider-outage.md)
   * AZ: [az-failure.md](az-failure.md)
   * Load: [traffic-spike.md](traffic-spike.md)
5. **Communicate.** If the 1 h/5 m (14.4×) alert keeps firing for more than 15 minutes, declare an incident and update the status page.
6. **Budget policy.** Record budget consumed. If the 30-day budget is exhausted, freeze features for the service (`monitoring/slo/slos.md`).
