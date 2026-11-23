# VPC Setup

**Status:** ✅ `terraform/modules/vpc` (called by `terraform/modules/rems-environment/network.tf`). ⚠️ Not applied.

## Objective

A 3-AZ VPC per environment with public, private-app, private-data and intra tiers, a NAT per AZ, flow logs and private access to AWS APIs.

## Prerequisites

* Account bootstrap done (state bucket exists): [IAM configuration](iam-configuration.md).
* CIDR ranges that don't overlap: 10.10/16 dev, 10.20/16 staging, 10.30/16 prod, 10.40/16 prod-dr. 🟡 Confirm with your network team that they don't clash with corporate or customer ranges (placeholder `10.100.0.0/16` VPN, `172.31.0.0/16` customer DB).
* Optional: Transit Gateway ID from the Network account (`transit_gateway_id`).

## AWS services

Amazon VPC, Internet Gateway, NAT Gateway, Elastic IP, VPC endpoints, VPC Flow Logs, CloudWatch Logs, (optional) Transit Gateway attachment.

## Terraform configuration

`terraform/environments/prod/main.tf` (excerpt; the values are real file content):

```hcl
module "rems" {
  source      = "../../modules/rems-environment"
  environment = "prod"
  site        = "primary"
  azs         = var.azs

  vpc_cidr                  = "10.30.0.0/16"
  single_nat_gateway        = false
  transit_gateway_id        = var.transit_gateway_id
  transit_gateway_routes    = var.customer_db_cidrs
  flow_logs_destination_arn = var.flow_logs_destination_arn
  # ...
}
```

Module inputs (`terraform/modules/vpc/variables.tf`): `name`, `cidr_block`, `azs`, `cluster_name` (for the `kubernetes.io/*` and `karpenter.sh/discovery` subnet tags), `single_nat_gateway`, `interface_endpoints` (16 defaults), `transit_gateway_id`, `transit_gateway_routes`, `flow_logs_destination_arn`, `flow_logs_retention_days`, `logs_kms_key_arn`, `tags`. `terraform/modules/rems-environment/network.tf` wires them from the environment inputs.

## Steps

```bash
cd terraform/environments/dev
export AWS_PROFILE=rems-dev-admin
terraform init -backend-config=backend.hcl
terraform plan -target=module.rems.module.vpc -out=vpc.tfplan   # optional: review the network alone first
terraform apply vpc.tfplan
```

In normal operation the whole environment is applied together (see [infrastructure deployment](infrastructure-deployment.md)). `-target` is only for a staged first review.

## Verification

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=rems-dev --query 'Vpcs[0].VpcId' --output text)
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[].{AZ:AvailabilityZone,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' --output table
aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --query 'NatGateways[].{AZ:SubnetId,State:State}'
aws ec2 describe-flow-logs --filter Name=resource-id,Values=$VPC_ID
```

Expected: 12 subnets (4 tiers × 3 AZs). NAT count is 1 in dev and 3 elsewhere. One flow log with `ALL` traffic. The `Name` tag pattern comes from the module. If your tags differ, filter by `tag:Environment`.

## Security considerations

* The default security group has all rules removed (`aws_default_security_group`).
* Data subnets have no route to the internet or NAT.
* Flow logs can go to the org Log Archive bucket (`flow_logs_destination_arn`) for tamper-resistant retention.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `InvalidSubnet.Conflict` | CIDR overlap with an existing VPC. Pick another /16 |
| `AddressLimitExceeded` | EIP quota (default 5 per region). Request an increase before creating 3 NATs + DR |
| Pods can't pull from ECR | ecr.api / ecr.dkr endpoints, or the S3 gateway endpoint on the app route tables, are missing |

## Rollback

`terraform destroy -target=module.rems.module.vpc` works only after everything inside the VPC is gone (EKS, Aurora, ALBs created by the controller). In practice, roll back the code change and `apply`. Delete Ingress objects first so the ALB controller removes its ALBs.
