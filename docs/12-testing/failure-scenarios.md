# Failure Scenarios (Chaos Engineering)

**Status:** ✅ AWS FIS templates and a driver script (`load-testing/chaos/`), runbooks for every scenario. ⚠️ No experiment has been run. FIS templates need real ARNs (role from the `fis_role_arn` output, subnets from `app_subnets_by_az`).

## Driver: `load-testing/chaos/run-chaos.sh`

| Command | Fault | Paired k6 scenario | Runbook |
|---|---|---|---|
| `./load-testing/chaos/run-chaos.sh az ap-south-1b` | FIS AZ power interruption (`fis-az-power-interruption.json`) | `az-failure.js` | `runbooks/az-failure.md` |
| `./load-testing/chaos/run-chaos.sh aurora` | FIS Aurora failover (`fis-aurora-failover.json`) | `db-bottleneck.js` (background) | `runbooks/postgres-bottleneck.md` |
| `./load-testing/chaos/run-chaos.sh redis` | `aws elasticache test-failover` per shard | `redis-failure.js` | `runbooks/redis-failure.md` |
| `./load-testing/chaos/run-chaos.sh ai-provider` | Bedrock VPC endpoint deny policy (`bedrock-endpoint-deny-policy.json`), then gateway scaled down | `ai-provider-failure.js` | `runbooks/ai-provider-outage.md` |
| (FIS) | EKS pod chaos (`fis-eks-pod-chaos.json`, RBAC `fis-k8s-rbac.yaml`) | normal-load | `runbooks/traffic-spike.md` |

## Steps

1. Prerequisites: staging deployed, `enable_fis = true` (staging and prod), FIS role output:

   ```bash
   terraform -chdir=terraform/environments/staging output -raw fis_role_arn
   terraform -chdir=terraform/environments/staging output -json app_subnets_by_az
   ```

2. The templates use tokens `ACCOUNT_ID`, `REGION`, `ENV` and `AZ_NAME`. `run-chaos.sh` renders them with `sed` (function `render`), creates the experiment template, starts it, and runs k6 in parallel (5-minute warm-up). It needs `BASE_URL` (and optionally `ACCESS_TOKEN`) in the environment:

   ```bash
   export ENV=staging AWS_REGION=ap-south-1 ACCOUNT_ID=<staging-account-id> KUBE_CONTEXT=rems-staging
   export BASE_URL=https://<staging-host>
   read -rs ACCESS_TOKEN && export ACCESS_TOKEN      # synthetic test tenant
   ./load-testing/chaos/run-chaos.sh az ap-south-1b
   ```

   Variables read by the script: `ENV` (default `staging`), `AWS_REGION` (default `ap-south-1`), `ACCOUNT_ID` (required), `BASE_URL`, `ACCESS_TOKEN`, `KUBE_CONTEXT`. Output goes to `load-testing/results/<timestamp>-<mode>/`.
3. Announce the drill in the on-call channel first.
4. Stop conditions: `fis-az-power-interruption.json` stops on the alarm `rems-ENV-core-writer-cpu-high`. `fis-aurora-failover.json` and `fis-eks-pod-chaos.json` have `"source": "none"`. 📋 Add an SLO burn-rate CloudWatch alarm as a stop condition before running them in prod game days.

## Abort

```bash
aws fis list-experiments --query "experiments[?state.status=='running'].id"
aws fis stop-experiment --id <experiment-id>
# AI drill: remove the endpoint deny policy (restore the default policy) and scale the gateway back via ArgoCD sync
```

## Why NetworkPolicies are not used for the AI-outage drill

NetworkPolicies are additive allow rules. You can't "subtract" Bedrock access with an extra policy while the gateway's allow rule exists. The drill uses an **endpoint policy deny** at the VPC endpoint plus scaling the gateway, which simulates both provider failure and gateway loss.

## Record results

Store k6 summaries and FIS experiment IDs in `load-testing/results/` (only `.gitkeep` today) and link them from [IMPLEMENTATION-STATUS](../IMPLEMENTATION-STATUS.md).
