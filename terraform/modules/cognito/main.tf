terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

# Cognito is the REMS token issuer. Enterprise tenants federate their own IdP
# (SAML/OIDC identity providers are added per tenant by the onboarding runbook).
# A pre-token-generation Lambda maps the IdP to custom:tenant_id and roles.

resource "aws_cognito_user_pool" "this" {
  name                     = var.name
  deletion_protection      = var.deletion_protection ? "ACTIVE" : "INACTIVE"
  mfa_configuration        = "OPTIONAL"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                     = "tenant_id"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = false
    required                 = false
    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }

  dynamic "lambda_config" {
    for_each = var.pre_token_generation_lambda_arn == null ? [] : [var.pre_token_generation_lambda_arn]
    content {
      pre_token_generation_config {
        lambda_arn     = lambda_config.value
        lambda_version = "V2_0"
      }
    }
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# Resource server for MCP OAuth scopes.
resource "aws_cognito_resource_server" "mcp" {
  identifier   = "mcp"
  name         = "REMS MCP"
  user_pool_id = aws_cognito_user_pool.this.id

  scope {
    scope_name        = "tools.read"
    scope_description = "Invoke read-only MCP tools"
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name                                 = "${var.name}-web"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false # SPA uses Authorization Code + PKCE
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = var.supported_identity_providers
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  access_token_validity                = 15
  id_token_validity                    = 15
  refresh_token_validity               = 12

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "hours"
  }
}

resource "aws_cognito_user_pool_client" "mcp" {
  name                                 = "${var.name}-mcp"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "${aws_cognito_resource_server.mcp.identifier}/tools.read"]
  callback_urls                        = var.mcp_callback_urls
  supported_identity_providers         = var.supported_identity_providers
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  access_token_validity                = 15
  refresh_token_validity               = 8

  token_validity_units {
    access_token  = "minutes"
    refresh_token = "hours"
  }
}
