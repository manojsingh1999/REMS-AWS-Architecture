# Connection Pooling (RDS Proxy)

**Status:** ✅ `aws_db_proxy*` in `terraform/modules/aurora-postgresql/main.tf` (read/write + read-only endpoints per cluster). ⚠️ Not applied. Application-side pool sizes are pending (service code).

## Objective

Absorb connection storms from autoscaling pods (up to 40 rems-api replicas), keep the Aurora connection count bounded, and make writer failovers faster and transparent to clients.

## Real configuration

```hcl
resource "aws_db_proxy" "this" {
  engine_family       = "POSTGRESQL"
  require_tls         = true
  idle_client_timeout = 1800
  # auth: one entry per service secret (IAM role reads Secrets Manager)
}

resource "aws_db_proxy_default_target_group" "this" {
  connection_pool_config {
    max_connections_percent      = 80
    max_idle_connections_percent = 20
    connection_borrow_timeout    = 30
  }
}
```

(Abbreviated from `terraform/modules/aurora-postgresql/main.tf`. Other arguments omitted.)

| Setting | Value | Meaning |
|---|---|---|
| `max_connections_percent` | 80 | Proxy uses ≤ 80 % of the DB `max_connections`, leaving room for admin and migrations |
| `max_idle_connections_percent` | 20 | Idle pool kept warm |
| `connection_borrow_timeout` | 30 s | Client waits up to 30 s for a pooled connection, then errors |
| `idle_client_timeout` | 1800 s | Idle client connections closed after 30 min |
| Read-only endpoint | `*_proxy_ro_endpoint` | Spreads read traffic over readers |

## Sizing guidance

Pod-side pool × max replicas should stay under the proxy limit, for example rems-api 40 pods × pool 10 = 400 client connections. The proxy multiplexes these onto fewer DB connections, unless sessions are **pinned**. Avoid session-level `SET`, temporary tables and advisory locks outside transactions. RLS uses `set_config(..., true)` (transaction-local), which doesn't pin.

## Verification

```bash
aws rds describe-db-proxy-targets --db-proxy-name <proxy-name>
aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DatabaseConnectionsCurrentlySessionPinned \
  --dimensions Name=ProxyName,Value=<proxy-name> --start-time <ISO> --end-time <ISO> --period 300 --statistics Maximum
```

The proxy name follows the module's naming. List with `aws rds describe-db-proxies --query 'DBProxies[].DBProxyName'`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `timeout waiting for connection from pool` | Borrow timeout hit. Raise proxy capacity (bigger writer instance) or reduce pod pool sizes |
| High pinning | Find session-level settings in the app. Use transaction-scoped settings |
| Failover > 30 s | Clients bypassing the proxy (direct cluster endpoint). Use the proxy endpoints only |

Runbook: `runbooks/postgres-bottleneck.md`. k6: `load-testing/k6/scenarios/db-bottleneck.js`.

## Rollback

Proxy settings change in place through Terraform. Clients can fall back to the cluster endpoint in an emergency (config change in microconfig).
