terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

# ------------------------------------------------------------------ IAM: control plane
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name                 = "${var.cluster_name}-cluster"
  assume_role_policy   = data.aws_iam_policy_document.cluster_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ------------------------------------------------------------------ logging
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.control_plane_log_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

# ------------------------------------------------------------------ cluster
resource "aws_security_group" "cluster_additional" {
  name        = "${var.cluster_name}-cluster-additional"
  description = "Additional SG for EKS control plane ENIs"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_name}-cluster-additional" })
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_allowed" {
  for_each          = toset(var.private_api_allowed_cidrs)
  security_group_id = aws_security_group.cluster_additional.id
  description       = "kube-apiserver from trusted private networks (VPN, CI runners)"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_eks_cluster" "this" {
  name                          = var.cluster_name
  version                       = var.kubernetes_version
  role_arn                      = aws_iam_role.cluster.arn
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = var.control_plane_subnet_ids
    security_group_ids      = [aws_security_group.cluster_additional.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = var.secrets_kms_key_arn
    }
  }

  upgrade_policy {
    support_type = var.support_type
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# Tag the EKS-managed cluster SG so Karpenter's EC2NodeClass can discover it.
resource "aws_ec2_tag" "cluster_sg_karpenter" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# ------------------------------------------------------------------ IAM: nodes
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name                 = "${var.cluster_name}-system-node"
  assume_role_policy   = data.aws_iam_policy_document.node_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# ------------------------------------------------------------------ system node group
resource "aws_launch_template" "system" {
  name_prefix            = "${var.cluster_name}-system-"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # pods cannot reach IMDS; Pod Identity is used instead
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.system_node_group.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.ebs_kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-system" })
  }

  tags = var.tags
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids
  ami_type        = var.system_node_group.ami_type
  capacity_type   = "ON_DEMAND"
  instance_types  = var.system_node_group.instance_types

  scaling_config {
    min_size     = var.system_node_group.min_size
    max_size     = var.system_node_group.max_size
    desired_size = var.system_node_group.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  labels = {
    "rems.io/node-pool" = "system"
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  # CNI and Pod Identity agent must exist before nodes join, otherwise nodes stay NotReady.
  depends_on = [aws_iam_role_policy_attachment.node, aws_iam_role_policy_attachment.node_cni, aws_eks_addon.pre_compute]
}

# ------------------------------------------------------------------ add-ons
resource "aws_iam_role_policy_attachment" "node_cni" {
  # VPC CNI uses the node role (pods have no IMDS access, so this is not exposed to workloads).
  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_addon" "pre_compute" {
  for_each = {
    "vpc-cni" = jsonencode({
      enableNetworkPolicy = "true"
      env = {
        ENABLE_PREFIX_DELEGATION = "true"
        WARM_PREFIX_TARGET       = "1"
        POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
      }
    })
    "kube-proxy"             = null
    "eks-pod-identity-agent" = null
  }
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = lookup(var.addon_versions, each.key, null)
  configuration_values        = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

# EBS CSI driver needs its own IAM via Pod Identity.
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name                 = "${var.cluster_name}-ebs-csi"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant", "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [var.ebs_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ebs_csi_kms" {
  name   = "kms"
  role   = aws_iam_role.ebs_csi.id
  policy = data.aws_iam_policy_document.ebs_csi_kms.json
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
  depends_on      = [aws_eks_addon.pre_compute]
}

resource "aws_eks_addon" "post_compute" {
  for_each = {
    "coredns" = jsonencode({
      replicaCount = 3
      tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
      topologySpreadConstraints = [{
        maxSkew           = 1
        topologyKey       = "topology.kubernetes.io/zone"
        whenUnsatisfiable = "ScheduleAnyway"
        labelSelector     = { matchLabels = { "k8s-app" = "kube-dns" } }
      }]
    })
    "aws-ebs-csi-driver" = jsonencode({
      controller = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }] }
    })
  }
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = lookup(var.addon_versions, each.key, null)
  configuration_values        = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.system, aws_eks_pod_identity_association.ebs_csi]
}

# ------------------------------------------------------------------ access entries (no aws-auth ConfigMap)
resource "aws_eks_access_entry" "this" {
  for_each          = var.access_entries
  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = length(each.value.kubernetes_groups) > 0 ? each.value.kubernetes_groups : null
  type              = "STANDARD"
  tags              = var.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each      = { for k, v in var.access_entries : k => v if v.policy_name != null }
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/${each.value.policy_name}"

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}
