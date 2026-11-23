# AWS Account Setup (Landing Zone)

**Status:** ✅ Terraform in `terraform/landing-zone/` (Organizations, OUs, 7 accounts, 7 SCPs + tag policy + suspended-OU deny-all, org CloudTrail, Log Archive bucket, delegated security services). 📋 IAM Identity Center permission sets are **not** created by Terraform. ⚠️ Not applied.

## Objective

Create an AWS Organization with separate accounts per function and environment, and guardrails that hold even against account administrators.

## Prerequisites

* A management (payer) account with root MFA enabled, and an admin role you can assume. Don't use the root user.
* A **state bucket in the management account**: `terraform/landing-zone/backend.hcl` expects `rems-tfstate-<mgmt-account-id>-ap-south-1`. 🟡 `terraform/global/bootstrap/` has no `mgmt.tfvars`. Create one (same shape as `prod.tfvars`, with `environment = "shared"`) or create the bucket manually before the first `init`.
* A mail domain where you control `aws+rems-*@<email_domain>` addresses. Each new account needs a unique root e-mail.
* Terraform ≥ 1.10, AWS CLI v2.

## AWS services

AWS Organizations, SCPs / tag policies / backup policies, CloudTrail (organization trail), S3 (Object Lock), GuardDuty, Security Hub, Inspector, IAM Access Analyzer, AWS Config.

## Accounts and OUs created (`terraform/landing-zone/main.tf`, `local.accounts`)

| Account key | OU | Root e-mail pattern |
|---|---|---|
| security | Security | `aws+rems-security@<email_domain>` |
| log-archive | Security | `aws+rems-log-archive@…` |
| network | Infrastructure | `aws+rems-network@…` |
| shared-services | Infrastructure | `aws+rems-shared@…` |
| rems-dev | Workloads/NonProd | `aws+rems-dev@…` |
| rems-staging | Workloads/NonProd | `aws+rems-staging@…` |
| rems-prod | Workloads/Prod | `aws+rems-prod@…` |

The DR region uses the **same prod account** (assumption in `documentation/02-assumptions.md`).

## SCP attachments (`terraform/landing-zone/scp.tf`; policy JSON in `security/iam/scp/`)

| SCP | Attached to |
|---|---|
| deny-leave-org-and-disable-security | Security, Infrastructure, Workloads, Sandbox |
| region-restriction (ap-south-1, ap-southeast-1 + global services) | Infrastructure, Workloads, Sandbox |
| deny-root-user | Security, Infrastructure, Workloads, Sandbox |
| protect-security-roles | Security, Infrastructure, Workloads |
| require-imdsv2-and-encryption | Workloads, Sandbox |
| deny-iam-users-and-keys | Workloads |
| prod-change-protection | Prod |
| suspended-deny-all | Suspended |

## Steps

1. Set the placeholders in `terraform/landing-zone/terraform.tfvars`:

   ```hcl
   email_domain            = "<your-mail-domain>"
   log_archive_bucket_name = "<globally-unique-bucket-name>"
   security_emails         = ["<security-team-address>"]
   ```

2. Confirm your identity is the management account:

   ```bash
   aws sts get-caller-identity --profile <mgmt-admin-profile>
   aws organizations describe-organization --profile <mgmt-admin-profile>   # error AWSOrganizationsNotInUseException = no org yet
   ```

3. Phase 1: create the organization, OUs and accounts first. Provider aliases `security` and `log_archive` need the new account IDs before anything else can be planned.

   ```bash
   cd terraform/landing-zone
   export AWS_PROFILE=<mgmt-admin-profile>
   terraform init -backend-config=backend.hcl
   terraform apply -target=aws_organizations_organization.this \
                   -target=aws_organizations_organizational_unit.top \
                   -target=aws_organizations_organizational_unit.workloads \
                   -target=aws_organizations_account.this
   ```

4. Phase 2: SCPs, delegated administrators, org trail, Log Archive bucket, security baseline.

   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   terraform output account_ids
   ```

5. Copy the real account IDs over the placeholders (`000000000000`, `111111111111`, `222222222222`, `333333333333`, `444444444444`) everywhere:

   ```bash
   grep -rln '111111111111\|222222222222\|333333333333\|444444444444' terraform helm kubernetes cicd monitoring ai-infrastructure
   ```

6. 📋 In IAM Identity Center, create the permission sets that the tfvars reference by ARN: `PlatformAdmin`, `ReadOnly`, `OnCall`. Assign them to groups. The generated role ARNs (`AWSReservedSSO_<name>_<suffix>`) go into `terraform/environments/<env>/terraform.tfvars`.

## Configuration explained

* `enabled_policy_types = ["SERVICE_CONTROL_POLICY","TAG_POLICY","BACKUP_POLICY"]`: SCPs are preventive. The tag policy `rems-required-tags` enforces the `Project` / `Environment` tags.
* `prevent_destroy` on the organization and accounts, plus `close_on_deletion = false`: a stray `destroy` can't close accounts.
* `iam_user_access_to_billing = "DENY"`: no billing access through IAM.

## Verification

```bash
aws organizations list-accounts --query 'Accounts[].{Name:Name,Id:Id,Status:Status}' --output table
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[].Name'
aws organizations list-delegated-administrators
aws cloudtrail describe-trails --query 'trailList[?IsOrganizationTrail]'
```

Expected: 7 new accounts in `ACTIVE` state, the SCP names from the table above, and Security Hub / GuardDuty / Inspector delegated to the security account.

## Security considerations

* The SCPs are applied to OUs, never to the root, so the management account itself is unaffected. **Test SCPs in Sandbox first.** `region-restriction` can block global services if the exemption list is incomplete.
* Lock the root user of every member account: MFA, then no further use. `deny-root-user` blocks root actions in member accounts.
* The Log Archive bucket uses Object Lock. Retention can't be shortened once it's set in compliance mode.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ConstraintViolationException: ACCOUNT_NUMBER_LIMIT_EXCEEDED` | Request an Organizations quota increase |
| Provider `security` fails on the first plan | Phase 1 wasn't run. Accounts must exist before the aliased providers can assume `OrganizationAccountAccessRole` |
| `AccessDenied` in member accounts after SCPs | Check `region-restriction` and `protect-security-roles`. Use `aws iam simulate-principal-policy` |
| Org is already managed by Control Tower | Import the OUs and accounts (`terraform import`) and keep only the SCP and security parts (see the comment in `main.tf`) |

## Rollback

* SCPs: detach with `aws organizations detach-policy --policy-id <p-id> --target-id <ou-id>`, or remove the entry from `local.scps` and apply.
* Accounts and the organization are protected by `prevent_destroy`. Closing an account is a manual, 90-day reversible process (`aws organizations close-account`). Don't automate it.
