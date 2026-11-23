# Security Groups

**Status:** ✅ Implemented (VPC, EKS, Aurora, ElastiCache modules). ⚠️ Not applied.

## Objective

Least-privilege network paths at the ENI level: data stores accept traffic only from the EKS cluster security group, and nothing accepts 0.0.0.0/0 except the internet-facing ALB, which the controller manages.

## Security groups

| SG | Module / resource | Ingress | Egress |
|---|---|---|---|
| VPC default | `modules/vpc` `aws_default_security_group.this` | none | none |
| VPC endpoints | `modules/vpc` `aws_security_group.endpoints` | 443 from VPC CIDR | – |
| EKS cluster SG (created by EKS) | `modules/eks` | control plane ↔ nodes | all |
| Additional cluster SG | `modules/eks` `aws_security_group` + `aws_vpc_security_group_ingress_rule` | 443 from `private_api_allowed_cidrs` (VPN) | all |
| Aurora DB | `modules/aurora-postgresql` `aws_security_group.db` | 5432 from `allowed_security_group_ids` (cluster SG) and from the proxy SG | – |
| RDS Proxy | `modules/aurora-postgresql` `aws_security_group.proxy` | 5432 from `allowed_security_group_ids` | 5432 to the DB SG only |
| ElastiCache Valkey | `modules/elasticache-redis` | 6379 from `allowed_security_group_ids` | – |
| ALB (public/internal) | Created by the AWS Load Balancer Controller | 443 (80 redirect) from the internet, or from VPC CIDR for the internal ALB | to targets |

Terraform example (verbatim from the Aurora module):

```hcl
# terraform/modules/aurora-postgresql/main.tf
resource "aws_vpc_security_group_ingress_rule" "db_from_clients" {
  for_each                     = toset(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from approved client SG"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
```

## Pods vs security groups

Pods use the **node / cluster SG** (Security Groups for Pods isn't enabled). Per-service isolation is done with Kubernetes NetworkPolicies, enforced by the VPC CNI network policy agent. See [network policies](../04-kubernetes/network-policies.md). This is a deliberate trade-off: SG-per-pod adds branch-ENI limits and slower pod start.

## Verification

```bash
aws ec2 describe-security-groups --filters Name=vpc-id,Values=<vpc-id> \
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName}' --output table
aws ec2 describe-security-group-rules --filters Name=group-id,Values=<aurora-sg-id> --output table
# Any world-open rule other than the ALB?
aws ec2 describe-security-group-rules --query "SecurityGroupRules[?CidrIpv4=='0.0.0.0/0' && !IsEgress]"
```

## Security considerations

* Security Hub control EC2.19 / EC2.18 flags unrestricted ports. Expect findings only for the ALB 443/80.
* Don't add CIDR-based ingress to data stores. Use SG references, so the rule follows the nodes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App times out to Aurora | The node isn't in the cluster SG (custom launch template?) or the NetworkPolicy blocks egress. Check both |
| `DependencyViolation` on destroy | ENIs (ALB, endpoints) still attached. Remove the Ingresses first |

## Rollback

Revert the module change and apply. SG rule changes are applied in place and don't recreate the group.
