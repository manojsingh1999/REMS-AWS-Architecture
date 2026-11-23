# Runbook: PostgreSQL becomes the primary bottleneck

**Alerts:** `rems-prod-core-writer-cpu-high`, `…-connections-high`, `…-replica-lag`, latency SLO burn across several services at once.

## Triage (10 minutes)

1. **Performance Insights** (DB load by wait event and top SQL): CPU, IO:DataFileRead, Lock:transactionid, or LWLock.
2. **RDS Proxy** metrics: `ClientConnections`, `DatabaseConnectionsBorrowLatency` and `DatabaseConnectionsCurrentlySessionPinned`. High pinning means an app is using session state, so check its SET statements.
3. Which cluster? `rems-core` (OLTP) or `rems-rag` (vector search and ingestion)? They're isolated on purpose.
4. Run the queries below on the writer (role `rems_monitoring`):

```sql
SELECT pid, now() - query_start AS age, state, wait_event_type, wait_event, left(query, 120)
FROM pg_stat_activity WHERE state <> 'idle' ORDER BY age DESC LIMIT 20;

SELECT queryid, calls, round(total_exec_time) AS total_ms, round(mean_exec_time, 1) AS mean_ms, left(query, 100)
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 15;
```

## Mitigations, from fastest to most durable

| Lever | How | Time |
|---|---|---|
| Kill the runaway query | `SELECT pg_cancel_backend(pid)` (then `pg_terminate_backend`) | seconds |
| Shed or limit non-critical load | Pause data-governance scans and RAG ingestion (scale to 0 via PR or KEDA pause annotation). Raise the API cache TTL | minutes |
| Move reads to readers | Make sure services use the proxy `-ro` endpoint for read paths. Readers auto scale to 5, or raise `autoscaling_max` | minutes |
| Scale the writer up | Change the instance class in tfvars (`db.r7g.2xlarge` → `4xlarge`). Aurora fails over to an upgraded reader first, about 30 s of disruption | 15–20 min |
| Fix the query | Add an index (`CREATE INDEX CONCURRENTLY`), fix N+1 queries, add pagination | hours–days |
| Structural | I/O-Optimized storage, partitioning large tenant tables by time, moving a heavy tenant to a silo cluster, moving analytics to replicas or an export | weeks |

## Guardrails already in place

`statement_timeout` per role (authz 2 s, api 15 s), `idle_in_transaction_session_timeout`, RDS Proxy `max_connections_percent` 80, app pools ≤ 10 per pod, and slow-query logs with `auto_explain`.

## Validate

Run k6 `db-bottleneck.js` in staging after any fix. The saturation point should rise, and background traffic should stay under 1 % errors.
