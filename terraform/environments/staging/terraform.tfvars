# PLACEHOLDER values - replace with real account data. No secrets belong in this file.
account_id              = "222222222222"
domain_name             = "staging.rems.example.com"
hosted_zone_id          = null # e.g. "Z0123456789ABCDEFGHIJ"
cognito_domain_prefix   = "rems-staging-example"
alert_emails            = ["rems-staging-alerts@example.com"]
platform_admin_role_arn = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_PlatformAdmin_0000000000000000"
readonly_role_arn       = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_ReadOnly_0000000000000000"
oncall_role_arn         = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_OnCall_0000000000000000"
cicd_deploy_role_arn    = "arn:aws:iam::222222222222:role/rems-staging-github-deploy"
private_api_allowed_cidrs = [
  "10.100.0.0/16", # PLACEHOLDER corporate VPN
]
monthly_budget_usd = 8000
