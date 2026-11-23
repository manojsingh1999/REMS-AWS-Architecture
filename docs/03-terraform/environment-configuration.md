# Environment Configuration

**Status:** ✅ Four environment roots. 🟡 All `terraform.tfvars` contain placeholders (account IDs, domains, role ARNs, e-mails).

## Differences between environments (from `terraform/environments/*/main.tf`)

| Setting | dev | staging | prod | prod-dr |
|---|---|---|---|---|
| Region | ap-south-1 | ap-south-1 | ap-south-1 | ap-southeast-1 |
| Account (placeholder) | 111111111111 | 222222222222 | 333333333333 | 333333333333 |
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 | 10.40.0.0/16 |
| `single_nat_gateway` | true | false | false | false |
| EKS public endpoint | only if `endpoint_public_access_cidrs` is non-empty | false | false | false |
| System node group | 2 × t4g.large | 3 × m7g.large | 3 × m7g.large (max 6) | 3 × m7g.large (max 6) |
| Aurora core | `db.serverless`, 0 readers | db.r7g.large, 1 reader | db.r7g.2xlarge, 2 readers, I/O-Optimized, max 5 | same classes as prod. **0 readers and no RDS Proxy until `dr_promoted = true`** |
| Aurora rag | `db.serverless`, 0 readers | db.r7g.large, 1 reader | db.r7g.xlarge, 1 reader, max 3 | same as prod, 0 readers until promoted |
| Valkey | cache.t4g.small, 1 shard | cache.r7g.large, 2 shards | cache.r7g.large, 3 shards × 1 replica | cache.r7g.large, 3 shards × 1 replica |
| `deletion_protection` | false | true | true | true |
| `enable_dr_replication` | false | false | true | – (it is the DR site) |
| `enable_fis` | false | true | true | false |
| `telemetry_retention_days` | 30 | 30 | 90 | 30 |
| Access entries | per tfvars | per tfvars | platform-admin, readonly, oncall, cicd | platform-admin, readonly |

The DR switches are in `terraform/modules/rems-environment/data.tf`: `reader_count = local.is_dr && !var.dr_promoted ? 0 : ...` and `enable_proxy = !local.is_dr || var.dr_promoted`.

## Variables to set (`terraform/environments/prod/variables.tf`)

| Variable | Example placeholder | Notes |
|---|---|---|
| `account_id` | `"333333333333"` | Enforced by `allowed_account_ids` |
| `region`, `dr_region`, `azs` | defaults | – |
| `domain_name`, `hosted_zone_id` | `"rems.example.com"`, `null` | With `hosted_zone_id = null`, no ACM certificate is created and `edge.certificate_arn` is null |
| `cognito_domain_prefix` | `"rems-prod-example"` | Must be globally unique |
| `alert_emails` | `["rems-oncall@example.com"]` | SNS subscriptions need e-mail confirmation |
| `platform_admin_role_arn`, `readonly_role_arn`, `oncall_role_arn`, `cicd_deploy_role_arn` | `arn:aws:iam::<acct>:role/aws-reserved/sso.amazonaws.com/...` | From Identity Center |
| `private_api_allowed_cidrs` | `["10.100.0.0/16"]` | VPN range (placeholder) |
| `transit_gateway_id`, `customer_db_cidrs` | `null`, `[]` | Data Governance connectivity (optional) |
| `flow_logs_destination_arn` | `null` | Log Archive bucket ARN |
| `permissions_boundary_arn` | from bootstrap output | – |
| `monthly_budget_usd` | `30000` | AWS Budgets alert |

prod-dr adds `primary_region`, `prod_state_bucket`, `prod_state_region` and `dr_promoted`.

## Steps

```bash
cd terraform/environments/staging
$EDITOR terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
```

## Security considerations

`terraform.tfvars` is committed and must stay secret-free. Put sensitive inputs in `TF_VAR_*` environment variables or Secrets Manager.

## Troubleshooting

`Error: AWS account ID not allowed`: the profile points at the wrong account (`allowed_account_ids`). This is a safety guard. Don't remove it.
