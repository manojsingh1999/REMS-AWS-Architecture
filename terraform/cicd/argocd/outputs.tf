output "argocd_url" {
  description = "ArgoCD UI (internal ALB, SSO)."
  value       = "https://${var.argocd_hostname}"
}

output "applicationset" {
  description = "ApplicationSet that deploys the REMS services from the microconfig repo."
  value       = "rems-services-${var.environment}"
}

output "deploy_key_fingerprints" {
  description = "Read-only deploy keys registered in GitHub for this cluster."
  value       = { for k, key in tls_private_key.repo : k => key.public_key_fingerprint_sha256 }
}
