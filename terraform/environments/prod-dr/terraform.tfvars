# PLACEHOLDER values - replace with real account data.
account_id              = "333333333333"
prod_state_bucket       = "rems-tfstate-333333333333-ap-south-1"
dr_promoted             = false
domain_name             = "rems.example.com"
cognito_domain_prefix   = "rems-prod-dr-example"
alert_emails            = ["rems-oncall@example.com"]
platform_admin_role_arn = "arn:aws:iam::333333333333:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_PlatformAdmin_0000000000000000"
readonly_role_arn       = "arn:aws:iam::333333333333:role/aws-reserved/sso.amazonaws.com/ap-south-1/AWSReservedSSO_ReadOnly_0000000000000000"
private_api_allowed_cidrs = ["10.100.0.0/16"] # PLACEHOLDER corporate VPN
