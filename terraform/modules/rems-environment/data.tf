locals {
  dr_secret_replicas = var.enable_dr_replication ? [{
    region      = var.dr_region
    kms_key_arn = module.kms_dr["secrets"].key_arn
  }] : []

  db_clients = [module.eks.cluster_security_group_id]
}

# ---------------------------------------------------------------- Aurora rems-core
module "aurora_core" {
  source = "../aurora-postgresql"

  name           = "${local.name}-core"
  environment    = var.environment
  instance_class = var.aurora_core.instance_class
  reader_count   = local.is_dr && !var.dr_promoted ? 0 : var.aurora_core.reader_count
  io_optimized   = var.aurora_core.io_optimized
  azs            = var.azs

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  proxy_subnet_ids           = module.vpc.data_subnet_ids
  allowed_security_group_ids = local.db_clients

  kms_key_arn            = local.is_dr ? lookup(var.dr_kms_key_arns, "aurora", module.kms["aurora"].key_arn) : module.kms["aurora"].key_arn
  secrets_kms_key_arn    = module.kms["secrets"].key_arn
  secret_replica_regions = local.dr_secret_replicas

  service_users = {
    "rems-api"              = { username = "rems_api", database = "rems_api" }
    "authorization-service" = { username = "rems_authz", database = "rems_authz" }
    "data-governance"       = { username = "rems_governance", database = "rems_governance" }
    "llm-gateway"           = { username = "rems_llmgw", database = "rems_llmgw" } # LiteLLM spend/budget store
  }

  backup_retention_days               = var.aurora_core.backup_retention_days
  performance_insights_retention_days = var.aurora_core.pi_retention_days
  deletion_protection                 = var.deletion_protection

  global_role               = local.aurora_global_role
  global_cluster_identifier = local.is_dr ? var.global_cluster_ids["core"] : null
  enable_proxy              = !local.is_dr || var.dr_promoted
  proxy_secret_arns         = lookup(var.dr_proxy_secret_arns, "core", [])

  reader_autoscaling = {
    enabled = !local.is_dr || var.dr_promoted
    min     = var.aurora_core.reader_count
    max     = var.aurora_core.autoscaling_max
  }

  tags = local.tags
}

# ---------------------------------------------------------------- Aurora rems-rag (pgvector)
module "aurora_rag" {
  source = "../aurora-postgresql"

  name           = "${local.name}-rag"
  environment    = var.environment
  instance_class = var.aurora_rag.instance_class
  reader_count   = local.is_dr && !var.dr_promoted ? 0 : var.aurora_rag.reader_count
  io_optimized   = var.aurora_rag.io_optimized
  azs            = var.azs

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  proxy_subnet_ids           = module.vpc.data_subnet_ids
  allowed_security_group_ids = local.db_clients

  kms_key_arn            = local.is_dr ? lookup(var.dr_kms_key_arns, "aurora", module.kms["aurora"].key_arn) : module.kms["aurora"].key_arn
  secrets_kms_key_arn    = module.kms["secrets"].key_arn
  secret_replica_regions = local.dr_secret_replicas

  service_users = {
    "metadata-rca" = { username = "rems_savvy", database = "rems_savvy" }
  }

  # Vector search and index builds: longer statement timeout.
  statement_timeout_ms = 120000

  backup_retention_days               = var.aurora_rag.backup_retention_days
  performance_insights_retention_days = var.aurora_rag.pi_retention_days
  deletion_protection                 = var.deletion_protection

  global_role               = local.aurora_global_role
  global_cluster_identifier = local.is_dr ? var.global_cluster_ids["rag"] : null
  enable_proxy              = !local.is_dr || var.dr_promoted
  proxy_secret_arns         = lookup(var.dr_proxy_secret_arns, "rag", [])

  reader_autoscaling = {
    enabled = !local.is_dr || var.dr_promoted
    min     = var.aurora_rag.reader_count
    max     = var.aurora_rag.autoscaling_max
  }

  tags = local.tags
}

# ---------------------------------------------------------------- ElastiCache Valkey
module "redis" {
  source = "../elasticache-redis"

  name               = "${local.name}-cache"
  environment        = var.environment
  node_type          = var.redis.node_type
  num_shards         = var.redis.num_shards
  replicas_per_shard = var.redis.replicas_per_shard

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = local.db_clients

  kms_key_arn            = module.kms["elasticache"].key_arn
  secrets_kms_key_arn    = module.kms["secrets"].key_arn
  logs_kms_key_arn       = module.kms["logs"].key_arn
  secret_replica_regions = local.dr_secret_replicas
  tags                   = local.tags
}
