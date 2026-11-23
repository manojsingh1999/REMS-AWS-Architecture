# Backend Configuration

**Status:** ✅ Partial S3 backends (`backend "s3" {}`) with per-environment `backend.hcl`, created by `terraform/global/bootstrap`. ⚠️ Buckets don't exist until the bootstrap is applied.

## Objective

Remote, encrypted, versioned and locked state per account and environment, replicated to the DR region for prod.

## Prerequisites

`terraform/global/bootstrap` applied in the account ([IAM configuration](../02-aws-infrastructure/iam-configuration.md)).

## Configuration (`terraform/environments/prod/backend.hcl`, real file)

```hcl
bucket       = "rems-tfstate-333333333333-ap-south-1" # PLACEHOLDER account ID
key          = "rems/prod/primary/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
kms_key_id   = "alias/rems-tfstate"
use_lockfile = true
```

| Setting | Meaning |
|---|---|
| `use_lockfile = true` | S3-native locking (Terraform ≥ 1.10). Writes a `.tflock` object, so no DynamoDB table is needed |
| `kms_key_id` | CMK created by bootstrap (`module "kms_state"`, alias `rems-tfstate`) |
| Bucket | Versioning, public access block, TLS-only policy, lifecycle on non-current versions (`modules/s3-bucket`) |
| DR | `replicate_state = true` (prod) creates `rems-tfstate-<acct>-ap-southeast-1` + CRR |

## State keys

| Stack | Key |
|---|---|
| landing-zone | `rems/landing-zone/terraform.tfstate` (management account bucket) |
| environments/&lt;env&gt; | `rems/<env>/primary/terraform.tfstate` |
| environments/prod-dr | `rems/prod/dr/terraform.tfstate` |
| cicd/argocd | `terraform/cicd/argocd/backends/<env>.hcl` |
| cicd/github | `terraform/cicd/github/backend.hcl` |
| global/bootstrap | local state file per environment (`-state=<env>.tfstate`). Optionally migrate to S3 afterwards |

## Steps

```bash
# Replace the placeholder account ID in every backend file
grep -rln 'rems-tfstate-' terraform --include=*.hcl
cd terraform/environments/prod
terraform init -backend-config=backend.hcl
# Moving the bootstrap's local state into S3 (optional):
cd ../../global/bootstrap && terraform init -migrate-state -backend-config=<your-bootstrap-backend.hcl>
```

🟡 The bootstrap stack has no `backend` block, so migration needs a `backend "s3" {}` block to be added first.

## Verification

```bash
aws s3api get-bucket-versioning --bucket rems-tfstate-<acct>-ap-south-1
aws s3api get-bucket-encryption --bucket rems-tfstate-<acct>-ap-south-1
aws s3 ls s3://rems-tfstate-<acct>-ap-south-1/rems/prod/primary/
terraform state list | head
```

## Security considerations

* Only the apply role and PlatformAdmin can read state. It contains endpoints and ARNs. Passwords are referenced through Secrets Manager, but `random_password` results **are** stored in state, which is why the bucket is KMS-encrypted and access-restricted.
* Never commit `*.tfstate` (covered by `.gitignore`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Error acquiring the state lock` | Another run is active. If it is really stale, `terraform force-unlock <LOCK_ID>` |
| `AccessDenied` on `kms:Decrypt` | Your role isn't a key user of `alias/rems-tfstate` |
| `Backend configuration changed` | `terraform init -reconfigure -backend-config=backend.hcl` |

## Rollback

Restore an older state version:

```bash
aws s3api list-object-versions --bucket <bucket> --prefix rems/prod/primary/terraform.tfstate
aws s3api get-object --bucket <bucket> --key rems/prod/primary/terraform.tfstate --version-id <id> restored.tfstate
terraform state push restored.tfstate     # only after confirming no apply is running
```
