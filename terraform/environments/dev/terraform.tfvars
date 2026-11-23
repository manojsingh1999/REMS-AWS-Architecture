# PLACEHOLDER values - replace with real account data. No secrets belong in this file.
account_id              = "111111111111"
domain_name             = "dev.rems.example.com"
hosted_zone_id          = null
cognito_domain_prefix   = "rems-dev-example"
alert_emails            = ["rems-dev-alerts@example.com"]
platform_admin_role_arn = "arn:aws:iam::111111111111:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_PlatformAdmin_0000000000000000"
readonly_role_arn       = "arn:aws:iam::111111111111:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_ReadOnly_0000000000000000"
cicd_deploy_role_arn    = "arn:aws:iam::111111111111:role/rems-dev-github-deploy"
endpoint_public_access_cidrs = [
  "203.0.113.0/24", # PLACEHOLDER office egress (RFC 5737 documentation range)
]
monthly_budget_usd = 3000
