variable "create_provider" {
  description = "Create the GitHub OIDC provider (once per account)."
  type        = bool
  default     = true
}

variable "existing_provider_arn" {
  description = "Existing provider ARN when create_provider = false."
  type        = string
  default     = null
}

variable "roles" {
  description = "Roles keyed by name. subjects use GitHub sub claims, e.g. repo:org/repo:environment:production."
  type = map(object({
    description              = string
    subjects                 = list(string)
    policy_json              = optional(string)
    managed_policy_arns      = optional(list(string), [])
    permissions_boundary_arn = optional(string)
    max_session_seconds      = optional(number, 3600)
  }))
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
