module "vpc" {
  source = "../vpc"

  name                      = local.name
  cidr_block                = var.vpc_cidr
  azs                       = var.azs
  cluster_name              = local.cluster_name
  single_nat_gateway        = var.single_nat_gateway
  transit_gateway_id        = var.transit_gateway_id
  transit_gateway_routes    = var.transit_gateway_routes
  flow_logs_destination_arn = var.flow_logs_destination_arn
  logs_kms_key_arn          = module.kms["logs"].key_arn
  tags                      = local.tags
}
