# IAM Security

**Status:** ✅ SCPs (`security/iam/scp/*.json`, attached by `terraform/landing-zone/scp.tf`), permission boundaries (`security/iam/permission-boundary-*.json`), OIDC roles, Pod Identity roles, Access Analyzer. 📋 Identity Center permission sets (manual). ⚠️ Not applied.

## Objective

Preventive and least-privilege controls across the four principal types: humans, CI, workloads and AWS services.

## Controls

| Layer | Control | File |
|---|---|---|
| Organization | 7 SCPs + tag policy + suspended deny-all | `security/iam/scp/`, `terraform/landing-zone/scp.tf` |
| Account | Permission boundaries on every Terraform-created role | `security/iam/permission-boundary-terraform.json`, `-workload.json` |
| Humans | Identity Center + MFA. Permission sets PlatformAdmin / ReadOnly / OnCall. EKS access entries | tfvars `*_role_arn`, `terraform/environments/*/main.tf` |
| CI | GitHub OIDC roles scoped to repo + environment. Plan vs apply split | `terraform/modules/github-oidc` |
| Workloads | One Pod Identity role per service account, boundary attached | `terraform/modules/rems-environment/identities.tf`, `policies/` |
| Detection | Access Analyzer, CloudTrail (org), GuardDuty, Security Hub | `terraform/modules/security-baseline` |

## SCP summary

| SCP | What it denies |
|---|---|
| `deny-root-user` | Any action by the root user in member accounts |
| `deny-iam-users-and-keys` | Long-lived credentials: IAM users and access keys (Workloads OU) |
| `deny-leave-org-and-disable-security` | Leaving the org, disabling CloudTrail / GuardDuty / Security Hub / Config / flow logs |
| `protect-security-roles` | Modifying the platform roles and the permission-boundary policies |
| `region-restriction` | Regional services outside ap-south-1 / ap-southeast-1 |
| `require-imdsv2-and-encryption` | EC2 without IMDSv2 (and downgrades), unencrypted EBS / RDS, public RDS, changes to S3 Block Public Access |
| `prod-change-protection` | Destructive actions without the break-glass role, and mutating calls from MCP / AI roles |

## Steps: verify least privilege

```bash
# What can a role really do? (boundary + SCP + identity policy)
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names s3:DeleteBucket iam:CreateUser kms:ScheduleKeyDeletion
# Unused permissions (after 90 days of traffic)
aws accessanalyzer start-policy-generation --policy-generation-details principalArn=<role-arn> \
  --cloud-trail-details '{"trails":[{"cloudTrailArn":"<org-trail-arn>","allRegions":true}],"accessRole":"<analyzer-role-arn>","startTime":"<ISO-8601>"}'
# External access findings
aws accessanalyzer list-findings --analyzer-arn <analyzer-arn>
```

## Example Pod Identity policy (real, `terraform/modules/rems-environment/identities.tf`)

```hcl
module "irsa_metadata_rca" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-metadata-rca"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.ai
  service_account          = "metadata-rca"
  policy_json              = data.aws_iam_policy_document.metadata_rca.json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}
```

`data.aws_iam_policy_document.metadata_rca` allows `s3:ListBucket` on the documents bucket, `s3:GetObject/PutObject/DeleteObject/GetObjectVersion` on `<documents-bucket>/tenants/*`, and `kms:Decrypt/GenerateDataKey` on the `s3` key. Most service policies are inline `aws_iam_policy_document`s in `identities.tf`. Only the AWS Load Balancer Controller policy is a JSON file (`policies/aws-load-balancer-controller.json`). mcp-server, rems-frontend, rems-api, authorization-service and chat-engine have **no** AWS role (they don't call AWS APIs directly).

## Verification

* `aws iam list-users` returns no users in workload accounts.
* Security Hub `IAM.*` controls pass.
* `kubectl auth can-i --list --as=system:serviceaccount:rems-ai:mcp-server` shows read-only verbs only.

## Troubleshooting

`AccessDenied` with `explicit deny in a service control policy` / `permissions boundary`: see [IAM configuration](../02-aws-infrastructure/iam-configuration.md#troubleshooting).

## Rollback

SCP changes are high-blast-radius. Test them on the Sandbox OU, attach to NonProd, then Prod. Detach a bad SCP immediately with `aws organizations detach-policy`.
