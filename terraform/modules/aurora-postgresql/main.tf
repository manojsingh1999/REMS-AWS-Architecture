terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  is_primary   = var.global_role != "secondary"
  create_proxy = var.enable_proxy
  instances = merge(
    { writer = { promotion_tier = 0, az = var.azs[0] } },
    { for i in range(var.reader_count) : "reader-${i + 1}" => { promotion_tier = 1, az = var.azs[(i + 1) % length(var.azs)] } }
  )
  secret_prefix = "rems/${var.environment}/aurora/${var.name}"
}

# ------------------------------------------------------------------ networking
resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "db" {
  name        = "${var.name}-aurora"
  description = "Aurora PostgreSQL ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-aurora" })
}

resource "aws_vpc_security_group_ingress_rule" "db_from_clients" {
  for_each                     = toset(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from approved client SG"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_proxy" {
  count                        = local.create_proxy ? 1 : 0
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from RDS Proxy"
  referenced_security_group_id = aws_security_group.proxy[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ------------------------------------------------------------------ parameters
resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-cluster-pg16"
  family      = "aurora-postgresql16"
  description = "REMS ${var.name} cluster parameters"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,auto_explain"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.slow_query_ms)
  }
  parameter {
    name  = "auto_explain.log_min_duration"
    value = tostring(var.slow_query_ms * 4)
  }
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "60000"
  }
  parameter {
    name  = "statement_timeout"
    value = tostring(var.statement_timeout_ms)
  }
  parameter {
    name  = "log_statement"
    value = "ddl" # audit schema changes without logging tenant data
  }
  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  tags = var.tags
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-instance-pg16"
  family      = "aurora-postgresql16"
  description = "REMS ${var.name} instance parameters"
  tags        = var.tags
}

# ------------------------------------------------------------------ credentials
# Aurora Global Database does not support RDS-managed master secrets, so the master
# password is generated here and stored in Secrets Manager (replicated to DR).
# Terraform state is encrypted with KMS in S3 and access-restricted (see terraform/global/bootstrap).
resource "random_password" "master" {
  count            = local.is_primary ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  count                   = local.is_primary ? 1 : 0
  name                    = "${local.secret_prefix}/master"
  description             = "Master credentials for ${var.name} (break-glass only)"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 30

  dynamic "replica" {
    for_each = var.secret_replica_regions
    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_arn
    }
  }
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "master" {
  count     = local.is_primary ? 1 : 0
  secret_id = aws_secretsmanager_secret.master[0].id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master[0].result
    host     = aws_rds_cluster.this.endpoint
    port     = 5432
    dbname   = "postgres"
  })
}

# One login role per REMS service. The SQL bootstrap (database/scripts/bootstrap-roles.sh)
# creates these roles with the same password and grants least privilege.
resource "random_password" "service" {
  for_each         = local.is_primary ? var.service_users : {}
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "service" {
  for_each                = local.is_primary ? var.service_users : {}
  name                    = "${local.secret_prefix}/${each.key}"
  description             = "DB credentials for ${each.key} (consumed via External Secrets + RDS Proxy)"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 30

  dynamic "replica" {
    for_each = var.secret_replica_regions
    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_arn
    }
  }
  tags = merge(var.tags, { Service = each.key })
}

resource "aws_secretsmanager_secret_version" "service" {
  for_each  = local.is_primary ? var.service_users : {}
  secret_id = aws_secretsmanager_secret.service[each.key].id
  secret_string = jsonencode({
    engine   = "postgres"
    username = each.value.username
    password = random_password.service[each.key].result
    host     = local.create_proxy ? aws_db_proxy.this[0].endpoint : aws_rds_cluster.this.endpoint
    ro_host  = local.create_proxy ? aws_db_proxy_endpoint.read_only[0].endpoint : aws_rds_cluster.this.reader_endpoint
    port     = 5432
    dbname   = each.value.database
    sslmode  = "verify-full"
  })
}

# ------------------------------------------------------------------ global database
resource "aws_rds_global_cluster" "this" {
  count                     = var.global_role == "primary" ? 1 : 0
  global_cluster_identifier = "${var.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# ------------------------------------------------------------------ cluster
resource "aws_rds_cluster" "this" {
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  engine_mode        = "provisioned"
  storage_type       = var.io_optimized ? "aurora-iopt1" : null

  global_cluster_identifier = var.global_role == "primary" ? aws_rds_global_cluster.this[0].id : (var.global_role == "secondary" ? var.global_cluster_identifier : null)

  master_username = local.is_primary ? var.master_username : null
  master_password = local.is_primary ? random_password.master[0].result : null
  database_name   = local.is_primary ? "postgres_admin" : null

  db_subnet_group_name             = aws_db_subnet_group.this.name
  vpc_security_group_ids           = [aws_security_group.db.id]
  db_cluster_parameter_group_name  = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_days
  preferred_backup_window             = "19:00-20:00" # 00:30-01:30 IST
  preferred_maintenance_window        = "sun:20:30-sun:21:30"
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = !var.deletion_protection
  final_snapshot_identifier           = var.deletion_protection ? "${var.name}-final" : null
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  apply_immediately                   = false
  allow_major_version_upgrade         = false

  serverlessv2_scaling_configuration {
    min_capacity = var.serverless_min_acu
    max_capacity = var.serverless_max_acu
  }

  tags = merge(var.tags, { backup = "rems-critical" })

  lifecycle {
    ignore_changes = [
      global_cluster_identifier, # managed during switchover/failover
      replication_source_identifier,
      master_password,
    ]
  }
}

# ------------------------------------------------------------------ instances
data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster_instance" "this" {
  for_each = local.instances

  identifier                            = "${var.name}-${each.key}"
  cluster_identifier                    = aws_rds_cluster.this.id
  engine                                = aws_rds_cluster.this.engine
  engine_version                        = aws_rds_cluster.this.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = each.value.az
  promotion_tier                        = each.value.promotion_tier
  db_subnet_group_name                  = aws_db_subnet_group.this.name
  db_parameter_group_name               = aws_db_parameter_group.this.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  monitoring_interval                   = 15
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_days
  copy_tags_to_snapshot                 = true
  tags                                  = var.tags
}

# ------------------------------------------------------------------ reader auto scaling
resource "aws_appautoscaling_target" "readers" {
  count              = local.is_primary && var.reader_autoscaling.enabled ? 1 : 0
  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.this.id}"
  min_capacity       = var.reader_autoscaling.min
  max_capacity       = var.reader_autoscaling.max
  depends_on         = [aws_rds_cluster_instance.this]
}

resource "aws_appautoscaling_policy" "readers" {
  count              = local.is_primary && var.reader_autoscaling.enabled ? 1 : 0
  name               = "${var.name}-reader-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.readers[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.readers[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.readers[0].resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    target_value       = var.reader_autoscaling.target_cpu
    scale_in_cooldown  = 600
    scale_out_cooldown = 120
  }
}

# ------------------------------------------------------------------ RDS Proxy (connection pooling)
resource "aws_security_group" "proxy" {
  count       = local.create_proxy ? 1 : 0
  name        = "${var.name}-rds-proxy"
  description = "RDS Proxy for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds-proxy" })
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_clients" {
  for_each                     = local.create_proxy ? toset(var.allowed_security_group_ids) : toset([])
  security_group_id            = aws_security_group.proxy[0].id
  description                  = "PostgreSQL from approved client SG"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_db" {
  count                        = local.create_proxy ? 1 : 0
  security_group_id            = aws_security_group.proxy[0].id
  description                  = "Proxy to Aurora"
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

data "aws_iam_policy_document" "proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  count              = local.create_proxy ? 1 : 0
  name               = "${var.name}-rds-proxy"
  assume_role_policy = data.aws_iam_policy_document.proxy_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "proxy" {
  count = local.create_proxy ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = local.is_primary ? [for s in aws_secretsmanager_secret.service : s.arn] : var.proxy_secret_arns
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "proxy" {
  count  = local.create_proxy ? 1 : 0
  name   = "read-db-secrets"
  role   = aws_iam_role.proxy[0].id
  policy = data.aws_iam_policy_document.proxy[0].json
}

resource "aws_db_proxy" "this" {
  count                  = local.create_proxy ? 1 : 0
  name                   = var.name
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy[0].arn
  vpc_subnet_ids         = var.proxy_subnet_ids
  vpc_security_group_ids = [aws_security_group.proxy[0].id]
  require_tls            = true
  idle_client_timeout    = 1800
  debug_logging          = false

  dynamic "auth" {
    for_each = local.is_primary ? { for k, s in aws_secretsmanager_secret.service : k => s.arn } : { for i, a in var.proxy_secret_arns : tostring(i) => a }
    content {
      auth_scheme = "SECRETS"
      secret_arn  = auth.value
      iam_auth    = var.proxy_iam_auth
      description = "service login ${auth.key}"
    }
  }
  tags = var.tags
}

resource "aws_db_proxy_default_target_group" "this" {
  count         = local.create_proxy ? 1 : 0
  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    max_connections_percent      = 80
    max_idle_connections_percent = 20
    connection_borrow_timeout    = 30
    # No session_pinning_filters: SET statements must pin, otherwise a session-level
    # tenant variable could leak to another client. Apps use transaction-local set_config().
  }
}

resource "aws_db_proxy_target" "this" {
  count                 = local.create_proxy ? 1 : 0
  db_proxy_name         = aws_db_proxy.this[0].name
  target_group_name     = aws_db_proxy_default_target_group.this[0].name
  db_cluster_identifier = aws_rds_cluster.this.id
  depends_on            = [aws_rds_cluster_instance.this]
}

resource "aws_db_proxy_endpoint" "read_only" {
  count                  = local.create_proxy ? 1 : 0
  db_proxy_name          = aws_db_proxy.this[0].name
  db_proxy_endpoint_name = "${var.name}-ro"
  vpc_subnet_ids         = var.proxy_subnet_ids
  vpc_security_group_ids = [aws_security_group.proxy[0].id]
  target_role            = "READ_ONLY"
  tags                   = var.tags
}
