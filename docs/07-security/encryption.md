# Encryption

**Status:** ✅ Implemented through `terraform/modules/kms` and per-service settings. ⚠️ Not applied.

## At rest: customer-managed KMS keys (`terraform/modules/rems-environment/kms.tf`)

| Key | Protects |
|---|---|
| eks | Kubernetes Secrets (envelope encryption) |
| ebs | Node and PV volumes (`aws_ebs_encryption_by_default` + default key) |
| aurora | Aurora storage, snapshots, Performance Insights |
| elasticache | Valkey at rest |
| s3 | Documents and telemetry buckets |
| secrets | Secrets Manager |
| logs | CloudWatch Logs (VPC flow logs, EKS, WAF, Valkey, FIS) |
| sns | Alert topics |
| backup | AWS Backup vaults |
| DR replicas (prod) | aurora, secrets, s3, backup in ap-southeast-1 |

Plus `rems-tfstate` for Terraform state (`terraform/global/bootstrap`). All keys have automatic rotation enabled, and `key_administrator_arns` separates administrators from users.

## In transit

| Path | Control |
|---|---|
| Client → ALB | TLS 1.2/1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`), HTTPS-only listener |
| ALB → pod | HTTP inside the VPC (📋 mTLS / service mesh not implemented, a documented trade-off) |
| App → Aurora / RDS Proxy | `rds.force_ssl = 1`, proxy `require_tls` |
| App → Valkey | `transit_encryption_mode = "required"` + AUTH |
| Pods → AWS APIs | TLS via interface endpoints |
| S3 | Bucket policies deny `aws:SecureTransport = false` |
| Bedrock / external LLMs | HTTPS. Bedrock through the private endpoint |

## Verification

```bash
aws kms list-aliases --query "Aliases[?starts_with(AliasName,'alias/rems')].AliasName"
aws kms get-key-rotation-status --key-id alias/<alias>
aws rds describe-db-clusters --query 'DBClusters[].{id:DBClusterIdentifier,enc:StorageEncrypted,kms:KmsKeyId}'
aws elasticache describe-replication-groups --query 'ReplicationGroups[].{id:ReplicationGroupId,atRest:AtRestEncryptionEnabled,transit:TransitEncryptionEnabled}'
aws ec2 get-ebs-encryption-by-default
```

The aliases depend on the naming in `modules/kms` (variable `alias`). List them first.

## Security considerations

* The SCP `require-imdsv2-and-encryption` blocks unencrypted resources even outside Terraform.
* A KMS key deletion has a waiting period (`deletion_window_in_days`). Treat any `ScheduleKeyDeletion` CloudTrail event as an incident.

## Rollback

`aws kms cancel-key-deletion --key-id <id>` during the waiting window. Key rotation is transparent and needs no rollback.
