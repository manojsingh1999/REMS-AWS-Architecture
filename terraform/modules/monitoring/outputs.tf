output "alerts_topic_arn" {
  description = "SNS topic for alerts (also used by Alertmanager SNS receiver)."
  value       = aws_sns_topic.alerts.arn
}

output "audit_log_group_name" {
  description = "Central audit log group."
  value       = aws_cloudwatch_log_group.audit.name
}
