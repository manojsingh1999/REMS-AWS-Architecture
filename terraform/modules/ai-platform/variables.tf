variable "name" {
  description = "Name prefix."
  type        = string
}

variable "environment" {
  description = "Environment."
  type        = string
}

variable "allowed_model_ids" {
  description = "Bedrock foundation model IDs (or inference profile ARNs) the gateway may invoke."
  type        = list(string)
  default = [
    "anthropic.claude-3-5-sonnet-20240620-v1:0",
    "anthropic.claude-3-haiku-20240307-v1:0",
    "amazon.titan-embed-text-v2:0",
  ]
}

variable "external_providers" {
  description = "Fallback providers that need an API key secret."
  type        = list(string)
  default     = ["openai", "anthropic"]
}

variable "kms_key_arn" {
  description = "KMS key for the guardrail."
  type        = string
  default     = null
}

variable "secrets_kms_key_arn" {
  description = "KMS key for provider key secrets."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for invocation logs."
  type        = string
  default     = null
}

variable "enable_invocation_logging" {
  description = "Account-level Bedrock invocation logging (one per account/region)."
  type        = bool
  default     = true
}

variable "invocation_log_retention_days" {
  description = "Retention for invocation logs."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
