output "web_acl_arn" {
  description = "Use in the ALB Ingress annotation alb.ingress.kubernetes.io/wafv2-acl-arn."
  value       = aws_wafv2_web_acl.this.arn
}
