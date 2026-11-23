# Subnet Configuration

**Status:** ✅ Implemented in `terraform/modules/vpc/main.tf` (`locals` + `aws_subnet.*`). ⚠️ Not applied.

## Objective

Deterministic per-AZ subnets sized for EKS prefix delegation, with tier-specific routing and Kubernetes discovery tags.

## Prerequisites

[VPC setup](vpc-setup.md).

## Computed layout

| Tier | Expression | dev 10.10/16 | staging 10.20/16 | prod 10.30/16 | prod-dr 10.40/16 |
|---|---|---|---|---|---|
| public (AZ a/b/c) | `cidrsubnet(cidr, 8, i)` | 10.10.0-2.0/24 | 10.20.0-2.0/24 | 10.30.0-2.0/24 | 10.40.0-2.0/24 |
| private-data | `cidrsubnet(cidr, 8, 3+i)` | 10.10.3-5.0/24 | 10.20.3-5.0/24 | 10.30.3-5.0/24 | 10.40.3-5.0/24 |
| intra | `cidrsubnet(cidr, 10, 24+i)` | 10.10.6.0/26, .64, .128 | same pattern | same pattern | same pattern |
| private-app | `cidrsubnet(cidr, 3, 1+i)` | 10.10.32/19, 64/19, 96/19 | … | 10.30.32/19, 64/19, 96/19 | … |

The `dataSubnetCIDRs` in `helm/environments/<env>/global.yaml` must match the private-data row. The charts use it for NetworkPolicy egress to Aurora and Valkey.

Check any CIDR locally without AWS:

```bash
terraform console <<'EOF'
cidrsubnet("10.30.0.0/16", 3, 1)
cidrsubnet("10.30.0.0/16", 10, 24)
EOF
```

## Tags and routing

| Tier | Tags | Route table |
|---|---|---|
| public | `kubernetes.io/role/elb = 1` | 0.0.0.0/0 → IGW |
| private-app | `kubernetes.io/role/internal-elb = 1`, `karpenter.sh/discovery = <cluster>` | 0.0.0.0/0 → NAT in the same AZ (one shared NAT in dev), TGW routes for `transit_gateway_routes`, S3 gateway endpoint |
| private-data | – | local only, S3 gateway endpoint |
| intra | – | local only (TGW routes when attached) |

The ALB controller uses the `kubernetes.io/role/*` tags to pick subnets. Karpenter's EC2NodeClass selects subnets by `karpenter.sh/discovery` (`kubernetes/base/karpenter.yaml`).

## Verification

```bash
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=rems-prod" \
  --query 'Subnets[].{AZ:AvailabilityZone,CIDR:CidrBlock,Free:AvailableIpAddressCount}' --output table
aws ec2 describe-route-tables --filters Name=vpc-id,Values=<vpc-id> \
  --query 'RouteTables[].{Id:RouteTableId,Routes:Routes[].DestinationCidrBlock}'
```

Expected: three app subnets, each with about 8 187 free addresses.

## Security considerations

Database subnet groups (`aws_db_subnet_group`, `aws_elasticache_subnet_group`) use **only** the private-data subnets.

## Troubleshooting

| Symptom | Fix |
|---|---|
| ALB controller: "unable to resolve at least one subnet" | Missing `kubernetes.io/role/elb` tag, or tags were edited manually |
| Karpenter: no subnets found | The `karpenter.sh/discovery` value differs from the cluster name |
| Pod IP exhaustion | Check that `ENABLE_PREFIX_DELEGATION` is on (`kubectl -n kube-system get ds aws-node -o yaml`) |

## Rollback

Subnet CIDRs can't change in place. A change forces replacement of everything in the subnet. Never change `vpc_cidr` on a live environment. Build a new environment and migrate instead.
