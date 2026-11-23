output "user_pool_id" {
  description = "User pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "issuer_url" {
  description = "OIDC issuer used by services to validate JWTs."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "web_client_id" {
  description = "SPA client ID."
  value       = aws_cognito_user_pool_client.web.id
}

output "mcp_client_id" {
  description = "MCP client ID."
  value       = aws_cognito_user_pool_client.mcp.id
}
