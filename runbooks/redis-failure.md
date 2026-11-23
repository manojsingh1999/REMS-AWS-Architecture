# Runbook: Redis / Valkey failure or degradation

**Alerts:** `…-engine-cpu`, `…-memory` (CloudWatch), latency SLO burn on rems-api/authz, `RemsExternalSecretSyncFailing` (auth token sync problems).

## Expected automatic behaviour

* Primary failure in a shard: Multi-AZ automatic failover promotes the replica in 30–60 s. Cluster-aware clients refresh the slot map on `MOVED` errors.
* Services treat Redis as optional (assumption A10). Caches fall through to Postgres and OPA, rate limiting fails open behind the WAF limits, and job producers retry with backoff.

## Diagnose

```bash
aws elasticache describe-events --source-type replication-group --duration 120
aws elasticache describe-replication-groups --replication-group-id rems-prod-cache \
  --query 'ReplicationGroups[0].{status:Status,nodes:NodeGroups[].NodeGroupMembers[].[CacheNodeId,CurrentRole,PreferredAvailabilityZone]}'
```

Check `EngineCPUUtilization` (single-threaded hot key?), `DatabaseMemoryUsagePercentage` and `Evictions`, `CurrConnections` (connection leaks after a deploy), and the slow log in CloudWatch `/aws/elasticache/rems-prod-cache/slow-log`.

## Actions

| Situation | Action |
|---|---|
| Failover in progress | Wait about 2 min. Confirm error rate recovery on the SLO dashboard |
| Memory pressure / evictions | Find big keys (`redis-cli --bigkeys` from a debug pod via the oncall role), shorten TTLs, or scale out shards (`num_shards` +1 in tfvars → online resharding) |
| Hot key / CPU | Check the key conventions in `database/redis/README.md`. Consider client-side caching or splitting the key |
| AUTH failures after rotation | Both tokens are valid during `ROTATE`. Make sure ExternalSecrets synced, then restart affected pods |
| Total loss | Recreate from the latest snapshot (or empty). Services rebuild caches, and queued jobs are re-enqueued from outbox tables |

Validate with `load-testing/chaos/run-chaos.sh redis` plus k6 `redis-failure.js`.
