# Redis (ElastiCache for Valkey) Setup

**Status:** ✅ `terraform/modules/elasticache-redis`, design notes in `database/redis/README.md`. ⚠️ Not applied. 🟡 Client behaviour (cluster-aware client, retry on `MOVED`, key conventions) has to be implemented in the services.

## Objective

A Multi-AZ, cluster-mode Valkey 7.2 used for caching, rate limits, chat sessions and job queues. It is **not** a system of record (assumption A10).

## Configuration

| Setting | Prod | Staging | Dev |
|---|---|---|---|
| Node type | cache.r7g.large | cache.r7g.large | cache.t4g.small |
| Shards × replicas | 3 × 1 | 2 × 1 | 1 × 1 |
| Encryption | TLS required + AUTH, CMK at rest | same | same |
| Eviction | `volatile-lru` (keys without TTL, such as queues, are protected) | same | same |
| Snapshots | daily, 7 days (module default `snapshot_retention_days = 7`) | same | same |

Secret: `rems/<env>/redis/rems-<env>-cache`, a JSON document with keys `auth_token`, `host` (configuration endpoint in cluster mode), `port` (6379), `tls` (true) and `cluster`. ESO consumes it.

## Key conventions (from `database/redis/README.md`)

```text
{t:<tenant_id>}:cache:<service>:<key>      TTL required
{t:<tenant_id>}:rl:<api>:<window>          TTL = window
{t:<tenant_id>}:sess:<session_id>          TTL = 12 h
q:<queue>                                  no TTL (protected from eviction)
llm:cache:<sha256(prompt+model)>           TTL 1 h
```

The `{t:<tenant_id>}` hash tag keeps a tenant's keys on one shard (multi-key ops work) and makes tenant scoping visible.

## Steps

1. Apply the environment (`module "redis"` in `terraform/modules/rems-environment/data.tf`).
2. Check connectivity from a pod that the NetworkPolicy allows to reach the data subnets on 6379:

   ```bash
   kubectl run valkey-cli -n rems --rm -it --restart=Never \
     --image=public.ecr.aws/docker/library/valkey:7.2 -- \
     valkey-cli -c --tls -h <configuration-endpoint> -p 6379 --askpass PING
   ```

   🟡 The test pod is blocked by the default-deny policy unless you label it like an allowed service. Run it in a debugging namespace with a temporary policy, or use the application's own health endpoint.

## Verification

```bash
terraform -chdir=terraform/environments/prod output -json redis
aws elasticache describe-replication-groups --replication-group-id <id> \
  --query 'ReplicationGroups[0].{status:Status,multiAZ:MultiAZ,autoFailover:AutomaticFailover,shards:length(NodeGroups)}'
```

## Security considerations

AUTH rotation uses the `ROTATE` → `DELETE` strategy, so the old and new tokens are valid during the change (see `security/secrets-rotation.md`). The SG allows 6379 only from the cluster SG.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `MOVED` errors | The client isn't cluster-aware. Use cluster mode in the client library |
| `NOAUTH` / `WRONGPASS` after rotation | Pods haven't refreshed the secret. Force-sync the ExternalSecret and restart |
| Memory > 80 % alarm | Check keys without TTL (`--bigkeys`, `MEMORY USAGE`). Scale shards (online resharding) |

Failure behaviour and drill: `runbooks/redis-failure.md`, k6 `load-testing/k6/scenarios/redis-failure.js`.

## Rollback

Node-type changes and resharding are online operations. Revert through Terraform. Data loss is acceptable by design (cache), and the services re-warm.
