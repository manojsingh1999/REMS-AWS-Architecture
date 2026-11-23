terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

locals {
  managed_rule_groups = [
    # name, priority, rules overridden to COUNT
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 10, count_rules = [] },
    { name = "AWSManagedRulesCommonRuleSet", priority = 20, count_rules = ["SizeRestrictions_BODY"] }, # OTLP payloads exceed 8 KB
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 30, count_rules = [] },
    { name = "AWSManagedRulesSQLiRuleSet", priority = 40, count_rules = [] },
    { name = "AWSManagedRulesLinuxRuleSet", priority = 50, count_rules = [] },
    { name = "AWSManagedRulesAnonymousIpList", priority = 60, count_rules = ["HostingProviderIPList"] },
  ]
}

resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = "REMS ${var.name} public ALB protection"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Per-IP rate limit (5-minute window).
  rule {
    name     = "rate-limit-per-ip"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_ip
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  # Stricter limit on authentication endpoints (credential stuffing).
  rule {
    name     = "rate-limit-auth"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_auth_per_ip
        aggregate_key_type = "IP"
        scope_down_statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = var.auth_path_prefix
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-auth"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = length(var.blocked_country_codes) > 0 ? [1] : []
    content {
      name     = "geo-block"
      priority = 3
      action {
        block {}
      }
      statement {
        geo_match_statement {
          country_codes = var.blocked_country_codes
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups
    content {
      name     = rule.value.name
      priority = rule.value.priority
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
          dynamic "rule_action_override" {
            for_each = rule.value.count_rules
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.name
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "waf" {
  # WAF requires the aws-waf-logs- prefix.
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
