output "account_ids" {
  description = "Account IDs by name (feed into tfvars of the other stacks)."
  value       = { for k, a in aws_organizations_account.this : k => a.id }
}

output "log_archive_bucket_arn" {
  description = "Use as flow_logs_destination_arn (append /vpc-flow-logs/)."
  value       = module.log_archive_bucket.bucket_arn
}
