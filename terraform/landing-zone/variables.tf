variable "region" {
  description = "Home region."
  type        = string
  default     = "ap-south-1"
}

variable "email_domain" {
  description = "Domain for account root emails (PLACEHOLDER)."
  type        = string
}

variable "log_archive_bucket_name" {
  description = "Globally unique name of the Log Archive bucket."
  type        = string
}

variable "security_emails" {
  description = "Security team distribution lists."
  type        = list(string)
  default     = []
}
