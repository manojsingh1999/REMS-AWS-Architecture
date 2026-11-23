module "waf" {
  source = "../waf"

  name              = local.name
  rate_limit_per_ip = var.waf_rate_limit_per_ip
  logs_kms_key_arn  = module.kms["logs"].key_arn
  tags              = local.tags
}

# ---------------------------------------------------------------- TLS certificates (ALB)
resource "aws_acm_certificate" "this" {
  count                     = var.hosted_zone_id == null ? 0 : 1
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  tags                      = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.hosted_zone_id == null ? {} : {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.hosted_zone_id == null ? 0 : 1
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

# ---------------------------------------------------------------- identity provider
module "cognito" {
  source = "../cognito"

  name                = local.name
  domain_prefix       = var.cognito_domain_prefix
  callback_urls       = ["https://app.${var.domain_name}/auth/callback"] # PLACEHOLDER route in the SPA
  logout_urls         = ["https://app.${var.domain_name}/"]
  deletion_protection = var.deletion_protection
  tags                = local.tags
}
