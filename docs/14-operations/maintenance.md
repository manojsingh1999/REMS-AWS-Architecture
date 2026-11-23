# Maintenance

**Status:** 📋 Procedures. Cadences are recommendations to adopt.

| Task | Cadence | How |
|---|---|---|
| EKS minor upgrade | Each new minor, within the standard support window | Bump `kubernetes_version` dev → staging → prod. Check add-on compatibility (`aws eks describe-addon-versions`) and deprecated APIs first |
| Node AMI refresh | Monthly / on CVE | Bump the `amiSelectorTerms` alias in `kubernetes/overlays/<env>` (prod pins `al2023@v20241115`). Karpenter drift replaces nodes within disruption budgets |
| Managed node group AMI | Monthly | `terraform apply` after the release version update (rolling, max unavailable 1) |
| Add-on chart versions | Monthly | Dependabot / Renovate PRs against `cicd/argocd/apps/<env>/platform-addons.yaml` |
| Aurora minor version | Quarterly | Auto minor upgrade in the maintenance window, or `terraform apply` with the new `engine_version` |
| Valkey engine | Yearly | `engine_version` in `modules/elasticache-redis` (online) |
| Secret rotation | 90/180 days | `security/secrets-rotation.md`, `database/scripts/rotate-service-password.sh` |
| KMS key rotation | Automatic yearly | – |
| Restore drill | Monthly | [backup strategy](../11-ha-dr/backup-strategy.md) |
| DR switchover drill | Twice a year | [recovery runbook](../11-ha-dr/recovery-runbook.md) |
| AZ chaos drill (staging) | Quarterly | `./load-testing/chaos/run-chaos.sh az <az>` |
| Access review (Identity Center, access entries) | Quarterly | `aws eks list-access-entries`, Identity Center assignments |
| Cost review | Monthly | Cost Explorer by `Environment` tag, `python3 scripts/cost_model.py` vs actual |
| Capacity review | Monthly | `documentation/05-capacity-plan.md` vs dashboards |
| Image re-scan triage | Daily (automated) | `security-scan.yml` findings |

## Maintenance windows

The prod ArgoCD sync window allows deploys from 04:30 UTC for 8 h on Mon–Thu (Terraform-managed variant). Karpenter's ai NodePool blocks voluntary disruption 09:00–19:00 IST on weekdays.

## Pre-maintenance checklist

1. Announce in the on-call channel and on the status page (if user-visible).
2. Error budget healthy. No active incident.
3. Rollback plan written in the change ticket.
4. Run in dev and staging first, with the same procedure.
