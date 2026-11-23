# EKS Setup

**Status:** ✅ `terraform/modules/eks`, `terraform/modules/karpenter`, `terraform/modules/pod-identity`, wired in `terraform/modules/rems-environment/eks.tf` and `identities.tf`. ⚠️ Not applied.

## Objective

A private EKS 1.31 cluster with a small managed system node group. Karpenter provides all workload capacity. Access is through EKS access entries, and AWS access from pods through Pod Identity.

## Prerequisites

* [VPC](vpc-setup.md) in place (same apply).
* IAM Identity Center role ARNs in `terraform/environments/<env>/terraform.tfvars` (`platform_admin_role_arn`, `readonly_role_arn`, `oncall_role_arn`, `cicd_deploy_role_arn`).
* Network path to the private API endpoint (VPN in `private_api_allowed_cidrs`, or an SSM bastion). Dev can enable `endpoint_public_access` with a CIDR allow-list.
* kubectl 1.31, AWS CLI v2.

## AWS services

Amazon EKS, EC2 (managed node group, launch template), IAM, KMS, CloudWatch Logs, SQS + EventBridge (Karpenter interruption handling).

## Terraform configuration (`terraform/environments/prod/main.tf`, real values)

```hcl
  kubernetes_version        = "1.31"
  endpoint_public_access    = false
  private_api_allowed_cidrs = var.private_api_allowed_cidrs
  system_node_group = {
    instance_types = ["m7g.large"]
    min_size       = 3
    max_size       = 6
    desired_size   = 3
  }
  access_entries = {
    platform-admin = { principal_arn = var.platform_admin_role_arn, policy_name = "AmazonEKSClusterAdminPolicy" }
    readonly       = { principal_arn = var.readonly_role_arn, policy_name = "AmazonEKSViewPolicy" }
    oncall         = { principal_arn = var.oncall_role_arn, kubernetes_groups = ["rems-oncall"] }
    cicd           = { principal_arn = var.cicd_deploy_role_arn, policy_name = "AmazonEKSViewPolicy", namespaces = ["rems", "rems-ai", "argocd"] }
  }
```

`rems-oncall` is bound to the ClusterRole `rems-oncall` in `kubernetes/base/rbac.yaml`: it can read everything, restart and scale workloads, and abort/promote rollouts.

## Steps

1. Apply the environment (the cluster is part of `module.rems`). See [infrastructure deployment](infrastructure-deployment.md).
2. Get credentials as PlatformAdmin:

   ```bash
   aws sso login --profile rems-prod-admin
   aws eks update-kubeconfig --region ap-south-1 --name rems-prod --alias rems-prod --profile rems-prod-admin
   kubectl get nodes -L topology.kubernetes.io/zone,karpenter.sh/nodepool
   ```

3. Install the GitOps layer: `./scripts/bootstrap-cluster.sh prod`, or Terraform in `terraform/cicd/argocd` (see [ArgoCD setup](../06-cicd/argocd-setup.md)). ArgoCD then installs Karpenter (Helm), the NodePools, the ALB controller and the other add-ons.
4. Before the Karpenter sync, check the Terraform outputs against the committed values:

   ```bash
   terraform -chdir=terraform/environments/prod output -json karpenter
   # keys: interruption_queue, node_role_name
   ```

   * `interruption_queue` → `settings.interruptionQueue` in `kubernetes/platform-addons/karpenter/values-prod.yaml` (committed value: `rems-prod-karpenter`).
   * `node_role_name` → the EC2NodeClass `spec.role` patch in `kubernetes/overlays/prod/kustomization.yaml` (committed value: `rems-prod-karpenter-node`).

   The NodePool / EC2NodeClass objects are in `kubernetes/base/karpenter.yaml` with `CLUSTER_NAME` tokens. The overlays replace the role, discovery tags, zones and AMI alias per environment.

## Configuration explained

| Setting | Value | Reason |
|---|---|---|
| `authentication_mode` | `API` | Access entries only, no `aws-auth` drift |
| `bootstrap_cluster_creator_admin_permissions` | false | The Terraform role isn't a hidden cluster admin |
| Secrets encryption | KMS `eks` key | Envelope encryption of Kubernetes Secrets |
| vpc-cni | `ENABLE_PREFIX_DELEGATION=true`, network policy enabled | Pod density, NetworkPolicy enforcement |
| coredns | 3 replicas, spread across zones | DNS survives an AZ loss |
| System node group | taint `CriticalAddonsOnly` | Only add-ons run there |

## Verification

```bash
aws eks describe-cluster --name rems-prod --region ap-south-1 \
  --query 'cluster.{v:version,status:status,auth:accessConfig.authenticationMode,public:resourcesVpcConfig.endpointPublicAccess}'
aws eks list-addons --cluster-name rems-prod --region ap-south-1
kubectl -n kube-system get pods
kubectl get nodepools,ec2nodeclasses           # after the ArgoCD sync
kubectl auth can-i '*' '*' --all-namespaces     # yes only for PlatformAdmin
```

## Security considerations

* Private endpoint in staging, prod and DR. IMDS hop limit 1. Control-plane audit logs go to CloudWatch.
* Kyverno policies (`security/kyverno/policies.yaml`) enforce non-root, no privilege escalation, signed images from ECR and required resources.
* Upgrade one minor version at a time. Check deprecated APIs first (`kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `You must be logged in to the server (Unauthorized)` | No access entry for your role, or the wrong profile. Check with `aws sts get-caller-identity` and `aws eks list-access-entries` |
| kubectl times out | You aren't on the VPN / allowed CIDR (private endpoint) |
| Karpenter nodes don't join | The node role has no access entry (created by `modules/karpenter`), or the EC2NodeClass role name is wrong |
| Add-on `DEGRADED` | `aws eks describe-addon --addon-name <n>` shows the health issues. Usually a missing Pod Identity role |

## Rollback

* Version upgrades can't be rolled back. Test in dev/staging, take a Velero-style manifest backup (all manifests are in Git anyway), and upgrade.
* Configuration changes: revert in Git and `terraform apply`.
* Destroying a cluster: remove the ArgoCD apps and Ingresses first (ALBs, Karpenter nodes), then `terraform destroy`. Prod has `deletion_protection = true` on the data stores.
