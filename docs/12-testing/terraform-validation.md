# Terraform Validation

**Status:** ✅ Offline validation passes. ⚠️ `terraform validate` with real providers hasn't been run, because the Terraform binary and provider downloads were blocked in the environment that produced this repository. CI (`terraform.yml`, job `static`) runs it.

## Checks

| Check | Command | Last result in this repo |
|---|---|---|
| Formatting | `terraform fmt -check -recursive terraform` | not run (no binary) |
| Validate every stack/module | `terraform -chdir=<dir> init -backend=false && terraform -chdir=<dir> validate` | not run (no binary) |
| HCL parse + module wiring (offline) | `python3 scripts/tf_static_check.py terraform` | ✅ 26 directories pass |
| Lint | `tflint --recursive --config .tflint.hcl --chdir terraform` | not run |
| Security | `checkov -d terraform --config-file .checkov.yaml --framework terraform --quiet --compact` | ✅ 1 428 passed, 0 failed |
| Plan | `terraform plan` per environment | ⚠️ requires AWS credentials, not run |

## Run everything

```bash
./scripts/validate.sh terraform
```

`validate.sh` uses `terraform`, `tflint` and `checkov` when they're installed, and falls back to `tf_static_check.py` otherwise.

## What `tf_static_check.py` covers (and doesn't)

* ✅ Every `.tf` file parses. Every module call passes only variables the module declares, and all required variables. Referenced module outputs exist.
* ❌ Provider schema validation (argument names and types of AWS resources). Only `terraform validate` does that. Run it before the first apply.

## Plan review checklist

* No `destroy` / `-/+` on `aws_rds_cluster`, `aws_eks_cluster`, `aws_elasticache_replication_group`, `aws_s3_bucket`, `aws_kms_key`.
* IAM changes reviewed by security (CODEOWNERS).
* Cost impact estimated (`scripts/cost_model.py` or Infracost, 📋 not integrated).
