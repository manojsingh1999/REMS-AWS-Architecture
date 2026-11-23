# Terraform Installation

**Status:** ✅ Version constraints declared in every stack (`required_version = ">= 1.10"`, AWS provider `~> 5.80`, random `~> 3.6`). CI pins `TF_VERSION: "1.10.3"` (`.github/workflows/terraform.yml`).

## Objective

Install the same Terraform and tooling versions that CI uses, so local plans match pipeline plans.

## Prerequisites

Linux or macOS shell with `curl` and `unzip`, or a package manager.

## Steps

### Terraform 1.10.3 (matches CI)

```bash
TF_VERSION=1.10.3
OS=linux; ARCH=amd64        # darwin / arm64 as appropriate
curl -fsSLO "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${OS}_${ARCH}.zip"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_SHA256SUMS"
grep "terraform_${TF_VERSION}_${OS}_${ARCH}.zip" "terraform_${TF_VERSION}_SHA256SUMS" | sha256sum -c -
unzip "terraform_${TF_VERSION}_${OS}_${ARCH}.zip" && sudo install terraform /usr/local/bin/
terraform version
```

Alternative: `tfenv install 1.10.3 && tfenv use 1.10.3`.

### Supporting tools

| Tool | Purpose | Config in repo |
|---|---|---|
| tflint + AWS ruleset | Lint | `.tflint.hcl` |
| Checkov | IaC security scan | `.checkov.yaml` |
| AWS CLI v2 | Auth, verification | – |
| Python 3 + `python-hcl2` | Offline checker `scripts/tf_static_check.py` | – |

```bash
tflint --init --config .tflint.hcl
pip install checkov python-hcl2
```

### AWS authentication (no static keys)

```bash
aws configure sso --profile rems-dev-admin     # IAM Identity Center
aws sso login --profile rems-dev-admin
export AWS_PROFILE=rems-dev-admin
aws sts get-caller-identity
```

## Verification

```bash
terraform version            # Terraform v1.10.3
terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev validate
./scripts/validate.sh terraform
```

Expected: `Success! The configuration is valid.` and `PASS` lines from `validate.sh`.

## Security considerations

* Verify the SHA256 sums (above). Commit `.terraform.lock.hcl` after the first real `init`. 🟡 Lock files aren't committed yet because no online `init` has been run.
* Never export `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. The SCP `deny-iam-users-and-keys` blocks key creation in workload accounts.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Unsupported Terraform Core version` | Install ≥ 1.10 (needed for `use_lockfile`) |
| Provider download blocked by a proxy | Set `HTTPS_PROXY`, or use a provider mirror (`terraform providers mirror`) |

## Rollback

Switch versions with tfenv. State written by a newer Terraform may not be readable by an older one, so upgrade CI and laptops together.
