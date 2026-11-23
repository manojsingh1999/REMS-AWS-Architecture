terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  p      = data.aws_partition.current.partition
  region = data.aws_region.current.name
  model_arns = [
    for m in var.allowed_model_ids :
    startswith(m, "arn:") ? m : "arn:${local.p}:bedrock:${local.region}::foundation-model/${m}"
  ]
}

# ------------------------------------------------------------------ Guardrail (PII + prompt attack)
resource "aws_bedrock_guardrail" "this" {
  name                      = var.name
  description               = "REMS guardrail: PII redaction, secret blocking, prompt-attack filter"
  blocked_input_messaging   = "This request was blocked by the REMS AI safety policy."
  blocked_outputs_messaging = "The response was blocked by the REMS AI safety policy."
  kms_key_arn               = var.kms_key_arn

  content_policy_config {
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "HATE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = {
        EMAIL                    = "ANONYMIZE"
        PHONE                    = "ANONYMIZE"
        NAME                     = "ANONYMIZE"
        IP_ADDRESS               = "ANONYMIZE"
        AWS_ACCESS_KEY           = "BLOCK"
        AWS_SECRET_KEY           = "BLOCK"
        PASSWORD                 = "BLOCK"
        CREDIT_DEBIT_CARD_NUMBER = "BLOCK"
      }
      content {
        type   = pii_entities_config.key
        action = pii_entities_config.value
      }
    }

    regexes_config {
      name        = "bearer-token"
      description = "Bearer/JWT tokens in logs"
      pattern     = "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"
      action      = "ANONYMIZE"
    }
  }

  tags = var.tags
}

resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Managed by Terraform"
}

# ------------------------------------------------------------------ Invocation logging (audit)
resource "aws_cloudwatch_log_group" "invocations" {
  name              = "/rems/${var.environment}/bedrock-invocations"
  retention_in_days = var.invocation_log_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

data "aws_iam_policy_document" "logging_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "logging" {
  name               = "${var.name}-bedrock-logging"
  assume_role_policy = data.aws_iam_policy_document.logging_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "logging" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.invocations.arn}:*"]
  }
}

resource "aws_iam_role_policy" "logging" {
  name   = "bedrock-logging"
  role   = aws_iam_role.logging.id
  policy = data.aws_iam_policy_document.logging.json
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.enable_invocation_logging ? 1 : 0
  logging_config {
    embedding_data_delivery_enabled = false
    image_data_delivery_enabled     = false
    text_data_delivery_enabled      = true
    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.invocations.name
      role_arn       = aws_iam_role.logging.arn
    }
  }
}

# ------------------------------------------------------------------ external provider keys (values set out-of-band)
resource "aws_secretsmanager_secret" "provider_keys" {
  for_each                = toset(var.external_providers)
  name                    = "rems/${var.environment}/llm/${each.value}"
  description             = "API key for external LLM provider ${each.value} (fallback). Value set via runbook, never in Git."
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "gateway_master_key" {
  name                    = "rems/${var.environment}/llm/master-key"
  description             = "LiteLLM gateway admin/master key. Value set via runbook (onboarding), never in Git or Terraform state."
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 7
  tags                    = var.tags
}

# ------------------------------------------------------------------ least-privilege policy for the LLM gateway
data "aws_iam_policy_document" "gateway" {
  statement {
    sid       = "InvokeApprovedModelsOnly"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:Converse", "bedrock:ConverseStream"]
    resources = local.model_arns
  }
  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.this.guardrail_arn]
  }
  dynamic "statement" {
    for_each = length(var.external_providers) > 0 ? [1] : []
    content {
      sid       = "ReadProviderKeys"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [for s in aws_secretsmanager_secret.provider_keys : s.arn]
    }
  }
  statement {
    sid       = "DecryptSecrets"
    actions   = ["kms:Decrypt"]
    resources = compact([var.secrets_kms_key_arn, var.kms_key_arn])
  }
}
