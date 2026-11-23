output "endpoint" {
  description = "Configuration endpoint (cluster mode) or primary endpoint."
  value       = var.cluster_mode ? aws_elasticache_replication_group.this.configuration_endpoint_address : aws_elasticache_replication_group.this.primary_endpoint_address
}

output "replication_group_id" {
  description = "Replication group ID."
  value       = aws_elasticache_replication_group.this.id
}

output "security_group_id" {
  description = "Redis SG."
  value       = aws_security_group.this.id
}

output "auth_secret_name" {
  description = "Secrets Manager secret name holding the AUTH token."
  value       = aws_secretsmanager_secret.auth.name
}

output "auth_secret_arn" {
  description = "Secret ARN."
  value       = aws_secretsmanager_secret.auth.arn
}
