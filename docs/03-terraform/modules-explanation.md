# Terraform Modules

**Status:** ✅ All 17 modules implemented, `checkov` clean. ⚠️ Not applied.

| Module | Main resources | Key inputs | Key outputs |
|---|---|---|---|
| `kms` | `aws_kms_key` (rotation on), alias, optional multi-region replica | `alias`, `description`, `multi_region`, `primary_key_arn`, `key_administrator_arns`, `key_user_arns`, `service_principals` | `key_arn` |
| `vpc` | VPC, 4 subnet tiers × AZs, IGW, NAT, route tables, S3 gateway + interface endpoints, flow logs, TGW attachment | `name`, `cidr_block`, `azs`, `single_nat_gateway`, `interface_endpoints`, `transit_gateway_id` | `vpc_id`, subnet IDs, `app_subnets_by_az`, `nat_public_ips` |
| `eks` | Cluster (API auth mode, KMS secrets), managed system node group + launch template, add-ons, access entries, Pod Identity for EBS CSI | `cluster_name`, `kubernetes_version`, `system_node_group`, `access_entries`, `endpoint_public_access` | `cluster_name`, `cluster_endpoint`, cluster SG |
| `karpenter` | Controller role (Pod Identity), node role + access entry, SQS interruption queue, EventBridge rules | `cluster_name`, `namespace`, `service_account`, `ebs_kms_key_arn` | `node_role_name`, `interruption_queue_name` |
| `pod-identity` | IAM role + `aws_eks_pod_identity_association` | `role_name`, `cluster_name`, `namespace`, `service_account`, `policy_json`, `permissions_boundary_arn` | `role_arn` |
| `ecr` | Repositories (immutable tags, KMS), lifecycle, registry scanning (enhanced), replication, pull policy for workload accounts | `namespace`, `repositories`, `pull_account_ids`, `replication_regions`, `keep_image_count` | `repository_urls` |
| `aurora-postgresql` | Cluster + instances, parameter groups (`rds.force_ssl`, pg_stat_statements), Global DB, RDS Proxy (+ RO endpoint), reader auto scaling, per-service Secrets Manager secrets | `name`, `instance_class`, `reader_count`, `io_optimized`, `service_users`, `global_cluster_identifier` | proxy endpoints, `cluster_id`, `global_cluster_id`, secret names/ARNs |
| `elasticache-redis` | Valkey replication group (cluster mode, Multi-AZ, TLS + AUTH), parameter group, logs, AUTH secret | `node_type`, `engine`, `cluster_mode`, `num_shards`, `replicas_per_shard`, `allowed_security_group_ids` | `endpoint`, `auth_secret_name` |
| `s3-bucket` | Bucket + versioning, SSE-KMS, PAB, TLS policy, lifecycle, logging, Object Lock, CRR + RTC | `bucket_name`, `kms_key_arn`, `object_lock`, `lifecycle_rules`, `access_log_bucket`, `replication` | `bucket_id`, `bucket_arn` |
| `waf` | Web ACL: AWS managed rule groups + rate limit, logging | `rate_limit_per_ip`, `rate_limit_auth_per_ip`, `auth_path_prefix`, `blocked_country_codes` | `web_acl_arn` |
| `cognito` | User pool, domain, resource server, web + MCP clients | `domain_prefix`, `callback_urls`, `mcp_callback_urls`, `supported_identity_providers` | `issuer_url`, client IDs |
| `ai-platform` | Bedrock guardrail + version, invocation logging, provider key secrets, LLM gateway role | `allowed_model_ids`, `external_providers`, `enable_invocation_logging` | `guardrail_id`, `guardrail_version`, `provider_secret_names` |
| `monitoring` | SNS topic, CloudWatch alarms (EKS/Aurora/Valkey/ALB), audit log group + metric filters, Budgets, Cost Anomaly Detection | `alert_emails`, `pagerduty_endpoint`, `eks_cluster_name`, `aurora_cluster_ids`, `monthly_budget_usd` | `alerts_topic_arn` |
| `security-baseline` | GuardDuty (org), Security Hub (org, standards, aggregator), Inspector, Access Analyzer, Config aggregator, finding notifications | delegated admin account | – |
| `backup` | Vault, Vault Lock, plan (daily + monthly, cross-region copy), tag-based selection | `name`, `dr_vault_arn`, `daily_retention_days`, `enable_vault_lock` | `vault_arn` |
| `github-oidc` | OIDC provider, plan/apply roles with repo + environment conditions | `create_provider`, `existing_provider_arn`, `roles` (map of role → repo/environment subjects + policies) | role ARNs |
| `rems-environment` | Composition of all of the above for one environment | see `terraform/modules/rems-environment/variables.tf` | see [project structure](project-structure.md) |

## Example: calling `aurora-postgresql` (from `terraform/modules/rems-environment/data.tf`, abbreviated)

```hcl
module "aurora_core" {
  source = "../aurora-postgresql"

  name           = "${local.name}-core"
  environment    = var.environment
  instance_class = var.aurora_core.instance_class
  reader_count   = local.is_dr && !var.dr_promoted ? 0 : var.aurora_core.reader_count
  io_optimized   = var.aurora_core.io_optimized
  azs            = var.azs

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  proxy_subnet_ids           = module.vpc.data_subnet_ids
  allowed_security_group_ids = local.db_clients
  # ... KMS, secret replicas ...

  service_users = {
    "rems-api"              = { username = "rems_api", database = "rems_api" }
    "authorization-service" = { username = "rems_authz", database = "rems_authz" }
    "data-governance"       = { username = "rems_governance", database = "rems_governance" }
    "llm-gateway"           = { username = "rems_llmgw", database = "rems_llmgw" } # LiteLLM spend/budget store
  }
  # ... backup, Performance Insights, proxy, Global DB settings ...
}
```

> Lines marked `# ...` are omitted here. Read the full block in `data.tf` before copying it.

## Verification

```bash
python3 scripts/tf_static_check.py terraform          # every module call matches the module's variables
checkov -d terraform --config-file .checkov.yaml --framework terraform --quiet --compact
```

## Troubleshooting

* `Unsupported argument` in a module call: the variable name changed. `tf_static_check.py` reports it offline.
* Checkov skips are listed with justifications in `.checkov.yaml`.
