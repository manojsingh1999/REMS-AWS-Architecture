output "node_role_name" {
  description = "IAM role name to reference in EC2NodeClass spec.role."
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "IAM role ARN of Karpenter-launched nodes."
  value       = aws_iam_role.node.arn
}

output "controller_role_arn" {
  description = "Karpenter controller role ARN."
  value       = aws_iam_role.controller.arn
}

output "interruption_queue_name" {
  description = "SQS queue for settings.interruptionQueue in the Karpenter Helm chart."
  value       = aws_sqs_queue.interruption.name
}
