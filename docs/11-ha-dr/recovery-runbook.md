# Recovery Runbook (regional failover)

**Status:** ✅ The authoritative step-by-step procedure is [`runbooks/dr-regional-failover.md`](../../runbooks/dr-regional-failover.md). This page summarises it with the exact commands. ⚠️ Never executed. 📋 Steps that depend on items not yet implemented are marked.

## Decision

Declare DR when ap-south-1 has a confirmed multi-AZ or regional impairment expected to last > 30 min, or on AWS's recommendation. Owner: Incident Commander + Head of Platform.

## Pre-checks (continuous)

```bash
aws rds describe-global-clusters --query 'GlobalClusters[].{id:GlobalClusterIdentifier,members:GlobalClusterMembers[].{arn:DBClusterArn,writer:IsWriter}}'
kubectl --context rems-prod-dr -n argocd get applications
kubectl --context rems-prod-dr get externalsecrets -A
```

## Procedure (~75 min budget, RTO 2 h)

| # | Time | Action | Command |
|---|---|---|---|
| 1 | T+0–15 | Declare, freeze deploys, open the status page | ArgoCD: `argocd app set <app> --sync-policy none` for prod apps if reachable |
| 2 | T+15–25 | Promote data | `./database/scripts/aurora-failover.sh failover <core-global-id> <dr-core-cluster-arn>`, then the same for rag |
| 3 | T+25–40 | Promote DR infra | see below |
| 4 | T+40–55 | Scale apps | 📋 merge the prepared `dr-scale-up` PR in rems-microconfig (removes `minReplicas: 1` overrides in `values-prod-dr.yaml`) |
| 5 | T+55–70 | Verify | `./scripts/smoke-test.sh https://<dr-app-host> rems-prod-dr` |
| 6 | T+70–75 | Shift traffic | 📋 Route 53 failover (records not yet in Terraform). Until then, update the DNS record manually: `aws route53 change-resource-record-sets --hosted-zone-id <zone> --change-batch file://dr-dns.json` |
| 7 | T+75 | Communicate | Status page. Users re-authenticate |

Step 3 commands:

```bash
cd terraform/environments/prod-dr
terraform init -reconfigure -backend-config=backend-dr-region.hcl
# terraform.tfvars: dr_promoted = true; prod_state_bucket / prod_state_region -> the replicated state bucket in ap-southeast-1
terraform plan -out=tfplan
terraform apply tfplan
aws eks update-kubeconfig --region ap-southeast-1 --name rems-prod-dr --alias rems-prod-dr
```

Global cluster IDs follow `${name}-global` in `terraform/modules/aurora-postgresql/main.tf`, so they are `rems-prod-core-global` and `rems-prod-rag-global` (also in `terraform output -json aurora` → `core_global_id`, `rag_global_id`). Get the DR cluster ARNs from `aws rds describe-global-clusters`.

## Failback

1. Once ap-south-1 is healthy, re-add it as a secondary (or let `switchover` handle membership).
2. Planned `./database/scripts/aurora-failover.sh switchover <global-id> <primary-region-cluster-arn>` in a change window (RPO 0).
3. Set `dr_promoted = false`, re-apply prod-dr, restore DNS, and re-enable prod auto-sync.

## After action

A postmortem within 5 business days. Update RPO/RTO measurements in `documentation/completion-checklist.md`.
