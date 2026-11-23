# Terraform Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| `Error acquiring the state lock` | Concurrent run, or a crashed run left a `.tflock` | Wait. If it is stale, `terraform force-unlock <ID>` |
| `AWS account ID not allowed` | Wrong `AWS_PROFILE` | `aws sts get-caller-identity`, then switch profile |
| `AccessDenied ... explicit deny in a service control policy` | SCP (region, IMDSv2/encryption, prod change protection) | Check `security/iam/scp/*.json`. Use an allowed region / encrypted resource, or run as the protected break-glass role |
| `InvalidParameterCombination` on Aurora | Instance class not supported for the engine version or in the region | `aws rds describe-orderable-db-instance-options --engine aurora-postgresql --engine-version <v>` |
| ACM validation hangs | `hosted_zone_id` wrong, or the domain isn't delegated | `dig NS <domain>`. Check the `_acme`/CNAME records in Route 53 |
| `ResourceInUseException` deleting subnets/VPC | ALBs/ENIs created by Kubernetes controllers | Delete Ingresses and Karpenter nodes first, then destroy |
| Provider `aws.security` fails (landing zone) | Phase 1 not applied | Run the targeted apply for the organization and accounts first |
| `Error: Cycle` | Edited module outputs used as inputs in the same module | `terraform graph \| dot -Tsvg > g.svg` to inspect |
| Plan shows a diff every time on tags | Both `default_tags` and resource tags set the same key | Remove the duplicate key from the resource |
| `EntityAlreadyExists` for the OIDC provider | It already exists in the account | `terraform import module.github_oidc.aws_iam_openid_connect_provider.this <arn>` |
| Drift after console changes | Manual edits | `terraform plan -refresh-only`, then codify or revert |

## Offline diagnosis

```bash
./scripts/validate.sh terraform
python3 scripts/tf_static_check.py terraform
TF_LOG=DEBUG terraform plan 2> tf-debug.log     # never attach this log publicly: it can contain ARNs and tokens
```
