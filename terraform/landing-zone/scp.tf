locals {
  scp_dir = "${path.module}/../../security/iam/scp"

  # policy => list of targets (OU keys or "root")
  scps = {
    "deny-leave-org-and-disable-security" = ["Security", "Infrastructure", "Workloads", "Sandbox"]
    "region-restriction"                  = ["Infrastructure", "Workloads", "Sandbox"]
    "deny-root-user"                      = ["Security", "Infrastructure", "Workloads", "Sandbox"]
    "protect-security-roles"              = ["Security", "Infrastructure", "Workloads"]
    "require-imdsv2-and-encryption"       = ["Workloads", "Sandbox"]
    "deny-iam-users-and-keys"             = ["Workloads"]
    "prod-change-protection"              = ["Prod"]
  }

  scp_attachments = merge([
    for policy, targets in local.scps : {
      for t in targets : "${policy}|${t}" => { policy = policy, target = t }
    }
  ]...)
}

resource "aws_organizations_policy" "scp" {
  for_each    = local.scps
  name        = each.key
  description = "REMS guardrail: ${each.key}"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.scp_dir}/${each.key}.json")
}

resource "aws_organizations_policy_attachment" "scp" {
  for_each  = local.scp_attachments
  policy_id = aws_organizations_policy.scp[each.value.policy].id
  target_id = local.ou_ids[each.value.target]
}

# Deny everything in the Suspended OU.
resource "aws_organizations_policy" "suspended" {
  name        = "suspended-deny-all"
  description = "Quarantine for accounts being closed"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "DenyAll", Effect = "Deny", Action = "*", Resource = "*" }]
  })
}

resource "aws_organizations_policy_attachment" "suspended" {
  policy_id = aws_organizations_policy.suspended.id
  target_id = local.ou_ids["Suspended"]
}

# Tag policy: enforce the tags used by cost allocation and AWS Backup selection.
resource "aws_organizations_policy" "tags" {
  name = "rems-required-tags"
  type = "TAG_POLICY"
  content = jsonencode({
    tags = {
      Environment = {
        tag_key   = { "@@assign" = "Environment" }
        tag_value = { "@@assign" = ["dev", "staging", "prod", "shared"] }
      }
      Project = {
        tag_key = { "@@assign" = "Project" }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "tags" {
  policy_id = aws_organizations_policy.tags.id
  target_id = local.ou_ids["Workloads"]
}
