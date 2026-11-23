output "key_arn" {
  description = "ARN of the key (primary or replica)."
  value       = var.primary_key_arn == null ? aws_kms_key.this[0].arn : aws_kms_replica_key.this[0].arn
}

output "key_id" {
  description = "Key ID."
  value       = var.primary_key_arn == null ? aws_kms_key.this[0].key_id : aws_kms_replica_key.this[0].key_id
}

output "alias_arn" {
  description = "Alias ARN."
  value       = aws_kms_alias.this.arn
}
