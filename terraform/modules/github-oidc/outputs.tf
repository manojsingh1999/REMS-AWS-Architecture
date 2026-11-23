output "role_arns" {
  description = "Map role name -> ARN (store as GitHub environment variables, not secrets)."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "provider_arn" {
  description = "OIDC provider ARN."
  value       = local.provider_arn
}
