output "guardrail_id" {
  description = "Guardrail ID (LLM gateway config)."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_version" {
  description = "Published guardrail version."
  value       = aws_bedrock_guardrail_version.this.version
}

output "gateway_policy_json" {
  description = "Least-privilege IAM policy for the LLM gateway Pod Identity role."
  value       = data.aws_iam_policy_document.gateway.json
}

output "provider_secret_names" {
  description = "Secrets Manager names for external provider keys."
  value       = { for k, s in aws_secretsmanager_secret.provider_keys : k => s.name }
}
