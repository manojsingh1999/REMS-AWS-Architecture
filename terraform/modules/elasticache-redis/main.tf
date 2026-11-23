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

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "ElastiCache ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-redis" })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = toset(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  description                  = "Redis/Valkey from approved client SG"
  referenced_security_group_id = each.value
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "${var.name}-params"
  family      = var.parameter_group_family
  description = "REMS ${var.name}"

  parameter {
    name  = "cluster-enabled"
    value = var.cluster_mode ? "yes" : "no"
  }
  parameter {
    name  = "maxmemory-policy"
    value = var.maxmemory_policy
  }
  parameter {
    name  = "timeout"
    value = "300"
  }
  tags = var.tags
}

resource "random_password" "auth" {
  length           = 48
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "auth" {
  name                    = "rems/${var.environment}/redis/${var.name}"
  description             = "AUTH token and endpoint for ${var.name}"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 7

  dynamic "replica" {
    for_each = var.secret_replica_regions
    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_arn
    }
  }
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id = aws_secretsmanager_secret.auth.id
  secret_string = jsonencode({
    auth_token = random_password.auth.result
    host       = var.cluster_mode ? aws_elasticache_replication_group.this.configuration_endpoint_address : aws_elasticache_replication_group.this.primary_endpoint_address
    port       = 6379
    tls        = true
    cluster    = var.cluster_mode
  })
}

resource "aws_cloudwatch_log_group" "slowlog" {
  name              = "/aws/elasticache/${var.name}/slow-log"
  retention_in_days = 30
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "REMS ${var.environment} cache/queues"
  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379

  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]

  num_node_groups         = var.cluster_mode ? var.num_shards : null
  replicas_per_node_group = var.cluster_mode ? var.replicas_per_shard : null
  num_cache_clusters      = var.cluster_mode ? null : var.replicas_per_shard + 1

  automatic_failover_enabled = var.replicas_per_shard > 0
  multi_az_enabled           = var.replicas_per_shard > 0

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = random_password.auth.result
  auth_token_update_strategy = "ROTATE"

  snapshot_retention_limit   = var.snapshot_retention_days
  snapshot_window            = "18:00-19:00"
  maintenance_window         = "sun:21:30-sun:22:30"
  auto_minor_version_upgrade = true
  apply_immediately          = false

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slowlog.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = merge(var.tags, { backup = "rems-standard" })

  lifecycle {
    ignore_changes = [auth_token] # rotated out of band via Secrets Manager runbook
  }
}
