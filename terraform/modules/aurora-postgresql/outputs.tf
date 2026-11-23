output "cluster_id" {
  description = "Cluster identifier."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "writer_endpoint" {
  description = "Cluster writer endpoint."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Cluster reader endpoint."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "proxy_endpoint" {
  description = "RDS Proxy read/write endpoint (what applications use)."
  value       = var.enable_proxy ? aws_db_proxy.this[0].endpoint : null
}

output "proxy_read_only_endpoint" {
  description = "RDS Proxy read-only endpoint."
  value       = var.enable_proxy ? aws_db_proxy_endpoint.read_only[0].endpoint : null
}

output "security_group_id" {
  description = "DB security group."
  value       = aws_security_group.db.id
}

output "global_cluster_id" {
  description = "Global cluster ID (primary only)."
  value       = var.global_role == "primary" ? aws_rds_global_cluster.this[0].id : null
}

output "master_secret_arn" {
  description = "Master secret ARN (primary only)."
  value       = var.global_role != "secondary" ? aws_secretsmanager_secret.master[0].arn : null
}

output "service_secret_arns" {
  description = "Map service -> secret ARN."
  value       = { for k, s in aws_secretsmanager_secret.service : k => s.arn }
}

output "service_secret_names" {
  description = "Map service -> secret name (for ExternalSecret remoteRef)."
  value       = { for k, s in aws_secretsmanager_secret.service : k => s.name }
}
