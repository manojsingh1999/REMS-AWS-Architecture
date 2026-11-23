# ElastiCache for Valkey 7.2

| Setting | Prod | Why |
|---|---|---|
| Topology | Cluster mode enabled, 3 shards × (1 primary + 1 replica), primaries spread across 3 AZs | Horizontal write scaling. Losing one AZ costs at most one primary, which fails over to its replica |
| Failover | Multi-AZ automatic failover (~30–60 s) | Clients must be cluster-aware and retry `MOVED`/`CLUSTERDOWN` with backoff |
| Security | TLS in transit (`required`), AUTH token from Secrets Manager (rotation via `ROTATE` strategy), CMK at rest, SG only from the EKS cluster SG | |
| Eviction | `volatile-lru` | Only keys with a TTL (cache) are evicted. Queue and rate-limit keys without a TTL are protected |
| Backups | Daily snapshot, 7 days | Redis is not a system of record (assumption A10). Snapshots speed up warm-up only |
| Observability | Slow log → CloudWatch, alarms on EngineCPU > 75 % and memory > 80 % | |

## Key conventions (multi-tenant)

```
{t:<tenant_id>}:cache:<service>:<key>      TTL required      hash tag keeps a tenant's keys on one shard
{t:<tenant_id>}:rl:<api>:<window>          TTL = window      rate-limit counters
{t:<tenant_id>}:sess:<session_id>          TTL = 12 h        chat sessions
q:<queue>                                  no TTL            background job queues (protected from eviction)
llm:cache:<sha256(prompt+model)>           TTL 1 h           LLM gateway response cache (tenant id inside the hash input)
```

Tenant IDs in keys come from the verified JWT. Services never accept a key prefix from the client.

## Failure behaviour (scenario: Redis failure)

| Dependency | Behaviour when Redis is unavailable |
|---|---|
| Caches (API, authz decisions) | Fall through to Postgres/OPA. Higher latency, still correct. The circuit breaker stops reconnect storms |
| Rate limits | Fail open for authenticated tenants, with WAF per-IP limits as the backstop |
| Chat sessions | Users start a new session |
| Job queues | Producers retry with backoff. KEDA keeps workers at their minimum. Jobs are re-enqueued from Postgres outbox tables when Redis returns |

k6 scenario `load-testing/k6/scenarios/redis-failure.js` checks this behaviour, and the failure is injected with `aws elasticache test-failover` or FIS `aws:elasticache:replicationgroup-interrupt-az-power`.
