output "config_repo_ssh_url" {
  description = "SSH URL of the microconfig repo (ArgoCD repository credential)."
  value       = github_repository.config.ssh_clone_url
}

output "config_repo_full_name" {
  description = "owner/name of the microconfig repo."
  value       = github_repository.config.full_name
}

output "seeded_files" {
  description = "Values files created in the microconfig repo."
  value       = sort(keys(merge(local.seed_values, local.seed_globals)))
}
