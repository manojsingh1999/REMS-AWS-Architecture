# Runbook: Single Availability Zone failure

**Alerts:** `RemsAvailabilityZoneDegraded` (Prometheus), `rems-<env>-failed-nodes` (CloudWatch), AWS Health event. **Severity:** SEV-2. It becomes SEV-1 only if SLO burn continues for more than 15 minutes.

## What happens automatically (target: no customer-visible outage)

| Layer | Behaviour | Typical time |
|---|---|---|
| ALB | Health checks fail for targets in the AZ, and traffic shifts to healthy targets in the other 2 AZs | 10–30 s |
| Pods | Readiness probes fail and the endpoints are removed. Nodes go NotReady, and REMS pods are evicted after 60 s (`tolerationSeconds` set in `rems-common`, instead of the 300 s default) | 1–5 min |
| Capacity | min replicas are sized for N+1 AZs. HPA/KEDA add replicas, and Karpenter launches nodes **only in healthy AZs** (subnets in the dead AZ fail to launch, so it moves on) | 1–2 min |
| Aurora | If the writer was in the AZ, a reader in another AZ is promoted. RDS Proxy keeps client connections and replays them | < 30 s (proxy masks most of it) |
| ElastiCache | Shard primaries in the AZ fail over to replicas | 30–60 s |
| NAT / endpoints | Each AZ has its own NAT and endpoint ENIs, so the other AZs are unaffected (static stability) | 0 |

## Verify (15 minutes)

```bash
kubectl get nodes -L topology.kubernetes.io/zone,karpenter.sh/nodepool | sort -k6
kubectl get pods -n rems -o wide | awk '{print $7}' | sort | uniq -c        # pods per node
kubectl get nodeclaims                                                      # new capacity
aws rds describe-db-clusters --db-cluster-identifier rems-prod-core \
  --query 'DBClusters[0].DBClusterMembers[].[DBInstanceIdentifier,IsClusterWriter]'
aws elasticache describe-replication-groups --replication-group-id rems-prod-cache \
  --query 'ReplicationGroups[0].NodeGroups[].NodeGroupMembers[].[CacheNodeId,PreferredAvailabilityZone,CurrentRole]'
```

Check the Grafana `REMS / SLO overview` dashboard. Burn rate should fall back below 1× within about 10 minutes.

## Actions

1. **Freeze voluntary disruption.** Pause deployments by suspending ArgoCD sync for `rems-prod-*` or using the project sync window, and set the Karpenter budgets to `nodes: "0"` if consolidation churns.
2. If pods stay Pending, check `RemsKarpenterNodePoolNearLimit` and the ResourceQuota, and raise the NodePool `limits` via PR if needed.
3. If Aurora didn't fail over (for example, only the network is impaired), run `database/scripts/aurora-failover.sh az-test rems-prod-core`.
4. Optionally exclude the AZ: patch the NodePool zone requirement to the 2 healthy AZs via PR. Revert after the AWS Health event closes.
5. **Recovery:** after the AZ returns, Karpenter consolidation rebalances. Confirm topology spread (pods per zone) and remove any temporary patches.

## Validation cadence

Quarterly in staging, and yearly in prod as a game day: `load-testing/chaos/run-chaos.sh az <az>` with k6 `az-failure.js`.
