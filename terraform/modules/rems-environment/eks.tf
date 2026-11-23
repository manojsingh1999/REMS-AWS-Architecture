module "eks" {
  source = "../eks"

  cluster_name                 = local.cluster_name
  kubernetes_version           = var.kubernetes_version
  vpc_id                       = module.vpc.vpc_id
  control_plane_subnet_ids     = module.vpc.intra_subnet_ids
  node_subnet_ids              = module.vpc.app_subnet_ids
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  private_api_allowed_cidrs    = var.private_api_allowed_cidrs
  secrets_kms_key_arn          = module.kms["eks"].key_arn
  ebs_kms_key_arn              = module.kms["ebs"].key_arn
  logs_kms_key_arn             = module.kms["logs"].key_arn
  permissions_boundary_arn     = var.permissions_boundary_arn
  access_entries               = var.access_entries
  tags                         = local.tags

  system_node_group = {
    instance_types = var.system_node_group.instance_types
    min_size       = var.system_node_group.min_size
    max_size       = var.system_node_group.max_size
    desired_size   = var.system_node_group.desired_size
  }
}

module "karpenter" {
  source = "../karpenter"

  cluster_name             = module.eks.cluster_name
  ebs_kms_key_arn          = module.kms["ebs"].key_arn
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}
