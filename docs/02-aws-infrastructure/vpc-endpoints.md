# VPC Endpoints

**Status:** ✅ Implemented in `terraform/modules/vpc/main.tf` (`aws_vpc_endpoint.*`). ⚠️ Not applied.

## Objective

Keep AWS API traffic (ECR, STS, KMS, Secrets Manager, Bedrock, …) on the AWS network: lower NAT cost, no internet path for credentials, and endpoint policies as an extra control.

## Endpoints created

| Type | Services (`interface_endpoints` default) |
|---|---|
| Gateway | `s3` (app + data route tables) |
| Interface (private DNS on) | `ecr.api`, `ecr.dkr`, `sts`, `kms`, `secretsmanager`, `logs`, `monitoring`, `ssm`, `ssmmessages`, `ec2messages`, `ec2`, `elasticloadbalancing`, `eks`, `eks-auth`, `sqs`, `bedrock-runtime` |

`eks-auth` is required for **EKS Pod Identity**. `sqs` is required for the Karpenter interruption queue. `bedrock-runtime` is used by the LLM gateway.

## Customise

🟡 `terraform/modules/rems-environment/network.tf` doesn't pass `interface_endpoints`, so the module default (16 services) is used in every environment. To change the list, add the argument to the `module "vpc"` block there, for example:

```hcl
module "vpc" {
  source = "../vpc"
  # ... existing arguments ...
  interface_endpoints = [
    "ecr.api", "ecr.dkr", "sts", "kms", "secretsmanager", "logs", "monitoring",
    "ssm", "ssmmessages", "ec2messages", "ec2", "elasticloadbalancing", "eks", "eks-auth",
    "sqs", "bedrock-runtime", "bedrock-agent-runtime"
  ]
}
```

## Verification

```bash
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=<vpc-id> \
  --query 'VpcEndpoints[].{Svc:ServiceName,Type:VpcEndpointType,State:State,DNS:PrivateDnsEnabled}' --output table
# From a pod (debug image):
kubectl run -it --rm dnscheck --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- \
  nslookup secretsmanager.ap-south-1.amazonaws.com
```

Expected: 17 endpoints `available`. The nslookup answer is a private 10.x address.

## Security considerations

* The endpoint SG allows 443 from the VPC CIDR only.
* The chaos experiment `load-testing/chaos/bedrock-endpoint-deny-policy.json` is an endpoint policy that simulates a Bedrock outage. Apply it only during a drill (see [failure scenarios](../12-testing/failure-scenarios.md)).

## Cost

Each interface endpoint costs per AZ-hour plus per GB. 16 endpoints × 3 AZs are in the cost model (`scripts/cost_model.py`). In dev, consider trimming the list.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not connect to the endpoint URL` from pods | Private DNS is disabled, or the NetworkPolicy blocks 443 to the VPC CIDR. The charts allow `vpcCidr:443` |
| Pod Identity credentials fail | The `eks-auth` endpoint is missing |

## Rollback

Remove the service from the list and apply. Traffic falls back to NAT automatically (when NAT exists).
