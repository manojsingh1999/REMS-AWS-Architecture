output "guardduty_detector_id" {
  description = "GuardDuty detector ID in the delegated admin account."
  value       = aws_guardduty_detector.this.id
}

output "security_topic_arn" {
  description = "SNS topic for HIGH/CRITICAL findings."
  value       = aws_sns_topic.security.arn
}
