# ECR Integration

**Status:** ✅ `terraform/modules/ecr` + `terraform/global/shared-services`. ⚠️ Not applied.

## Objective

One registry in the Shared Services account (`444444444444` placeholder), replicated to the DR region and readable by the workload accounts. Pushes come only from the CI OIDC role.

## Prerequisites

Landing zone + Shared Services account. Workload account IDs known.

## Configuration

| Feature | Setting (module `ecr`) |
|---|---|
| Repositories | `rems/<service>` for the 7 services (variable `repositories`, `namespace = "rems"`) |
| Tag mutability | IMMUTABLE |
| Encryption | KMS (`kms_key_arn`) |
| Scanning | Registry-level enhanced scanning (Inspector), `manage_registry_scanning` |
| Lifecycle | Keep the last `keep_image_count` images |
| Replication | `replication_regions` (ap-southeast-1 for DR) |
| Cross-account pull | Repository policy for `pull_account_ids` (dev, staging, prod) |
| Push | Role `rems-github-ecr-push`, assumable only by GitHub OIDC from the allowed repos |

## Steps

```bash
cd terraform/global/shared-services
$EDITOR terraform.tfvars          # account_id, workload_account_ids, github_org, admin_role_arns
AWS_PROFILE=rems-shared-admin terraform init -backend-config=backend.hcl
AWS_PROFILE=rems-shared-admin terraform plan -out=tfplan
AWS_PROFILE=rems-shared-admin terraform apply tfplan
terraform output repository_urls
terraform output ecr_push_role_arn
```

Then set `ecr_registry` and `ecr_push_role_arn` in `terraform/cicd/github/terraform.tfvars`.

## Verification

```bash
aws ecr describe-repositories --registry-id <shared-acct> --query 'repositories[].{n:repositoryName,m:imageTagMutability}'
aws ecr get-registry-scanning-configuration
aws ecr describe-registry --query replicationConfiguration
aws ecr get-repository-policy --repository-name rems/rems-api
# From a workload node / pod (pull through the ecr.dkr VPC endpoint):
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <shared-acct>.dkr.ecr.ap-south-1.amazonaws.com
```

## Security considerations

* No account can push except through the CI role. Workload accounts are pull-only.
* Kyverno requires images from `*.dkr.ecr.*.amazonaws.com/rems/*` with a valid cosign signature.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Nodes: `403 Forbidden` pulling | The workload account isn't in `pull_account_ids`, or KMS key policy grants are missing |
| DR cluster can't pull | Replication not configured, or the image was pushed before replication was enabled. Re-push or copy it |

## Rollback

Revert and apply. Repositories have lifecycle protection. Don't delete repositories that running workloads reference.
