terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

# Out-of-band monitoring: these CloudWatch alarms keep working even if the in-cluster
# Prometheus/Alertmanager stack is down. They page through SNS -> PagerDuty/Email.

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = var.sns_kms_key_arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "https" {
  count                  = var.pagerduty_endpoint == null ? 0 : 1
  topic_arn              = aws_sns_topic.alerts.arn
  protocol               = "https"
  endpoint               = var.pagerduty_endpoint
  endpoint_auto_confirms = true
}

# ------------------------------------------------------------------ audit log group
resource "aws_cloudwatch_log_group" "audit" {
  name              = "/rems/${var.environment}/audit"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn
  tags              = merge(var.tags, { DataClass = "audit" })
}

resource "aws_cloudwatch_log_metric_filter" "mcp_denied" {
  name           = "${var.name}-mcp-denied"
  log_group_name = aws_cloudwatch_log_group.audit.name
  pattern        = "{ ($.component = \"mcp-server\" || $.component = \"authorization-service\") && $.decision = \"deny\" }"
  metric_transformation {
    name          = "AuthzDenied"
    namespace     = "REMS/${var.environment}/Security"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "mcp_denied_burst" {
  alarm_name          = "${var.name}-authz-deny-burst"
  alarm_description   = "Burst of denied authorization/MCP decisions - possible cross-tenant probing or compromised tool. Runbook: runbooks/compromised-mcp-tool.md"
  namespace           = "REMS/${var.environment}/Security"
  metric_name         = "AuthzDenied"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.authz_deny_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# ------------------------------------------------------------------ Aurora
resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  for_each            = toset(var.aurora_cluster_ids)
  alarm_name          = "${each.value}-writer-cpu-high"
  alarm_description   = "Aurora writer CPU > 80% for 10 min. Runbook: runbooks/postgres-bottleneck.md"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBClusterIdentifier = each.value, Role = "WRITER" }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  for_each            = toset(var.aurora_cluster_ids)
  alarm_name          = "${each.value}-connections-high"
  alarm_description   = "Aurora connections close to max_connections"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBClusterIdentifier = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.aurora_connections_threshold
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "aurora_replica_lag" {
  for_each            = toset(var.aurora_cluster_ids)
  alarm_name          = "${each.value}-replica-lag"
  alarm_description   = "Aurora reader lag > 1 s"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLagMaximum"
  dimensions          = { DBClusterIdentifier = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "aurora_global_lag" {
  for_each            = toset(var.aurora_global_cluster_ids)
  alarm_name          = "${each.value}-global-replication-lag"
  alarm_description   = "Aurora Global DB lag > 60 s threatens RPO 15 min. Runbook: runbooks/dr-regional-failover.md"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 60000
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# ------------------------------------------------------------------ ElastiCache
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  count               = var.redis_replication_group_id == null ? 0 : 1
  alarm_name          = "${var.redis_replication_group_id}-engine-cpu"
  alarm_description   = "Valkey/Redis engine CPU > 75%. Runbook: runbooks/redis-failure.md"
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  dimensions          = { ReplicationGroupId = var.redis_replication_group_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  threshold           = 75
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count               = var.redis_replication_group_id == null ? 0 : 1
  alarm_name          = "${var.redis_replication_group_id}-memory"
  alarm_description   = "Valkey/Redis memory > 80%"
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  dimensions          = { ReplicationGroupId = var.redis_replication_group_id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# ------------------------------------------------------------------ EKS (Container Insights)
resource "aws_cloudwatch_metric_alarm" "eks_failed_nodes" {
  alarm_name          = "${var.eks_cluster_name}-failed-nodes"
  alarm_description   = "Nodes failing in the cluster (possible AZ issue). Runbook: runbooks/az-failure.md"
  namespace           = "ContainerInsights"
  metric_name         = "cluster_failed_node_count"
  dimensions          = { ClusterName = var.eks_cluster_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# ------------------------------------------------------------------ Bedrock throttling
resource "aws_cloudwatch_metric_alarm" "bedrock_throttles" {
  alarm_name          = "${var.name}-bedrock-throttles"
  alarm_description   = "Bedrock throttling - LLM gateway will fall back. Runbook: runbooks/ai-provider-outage.md"
  namespace           = "AWS/Bedrock"
  metric_name         = "InvocationThrottles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 50
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# ------------------------------------------------------------------ cost guardrails
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Environment$%s", var.environment)]
  }

  dynamic "notification" {
    for_each = [{ t = 80, type = "ACTUAL" }, { t = 100, type = "FORECASTED" }]
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.t
      threshold_type            = "PERCENTAGE"
      notification_type         = notification.value.type
      subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
    }
  }
}

resource "aws_ce_anomaly_monitor" "services" {
  count             = var.create_cost_anomaly_monitor ? 1 : 0
  name              = "${var.name}-service-anomalies"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "services" {
  count     = var.create_cost_anomaly_monitor ? 1 : 0
  name      = "${var.name}-anomalies"
  frequency = "IMMEDIATE"

  monitor_arn_list = [aws_ce_anomaly_monitor.services[0].arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.cost_anomaly_threshold_usd)]
    }
  }
}

# SNS topic policy so Budgets / Cost Anomaly / CloudWatch can publish.
data "aws_iam_policy_document" "sns" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns.json
}
