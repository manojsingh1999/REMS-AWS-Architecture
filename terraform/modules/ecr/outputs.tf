output "repository_urls" {
  description = "Map service -> repository URL."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map service -> repository ARN."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
