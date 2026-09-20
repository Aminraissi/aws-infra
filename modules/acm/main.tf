# ---------------------------------------------------------------
# ACM – Two certificates for www.raissiamine.click
#
#   1. eu-west-1  → attached to the ALB (cluster region)
#   2. us-east-1  → attached to CloudFront (must be us-east-1)
#
# Both use DNS validation via the existing Route 53 hosted zone.
# The validation CNAME is the same for both certificates, so we
# use allow_overwrite = true and a merged for_each to avoid
# duplicate-record errors.
# ---------------------------------------------------------------

# ── Lookup the existing hosted zone ───────────────────────────
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ── Certificate 1 – eu-west-1 (ALB) ──────────────────────────
resource "aws_acm_certificate" "alb" {
  domain_name       = var.www_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.www_domain}-alb-cert" }
}

# ── Certificate 2 – us-east-1 (CloudFront) ───────────────────
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = var.www_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.www_domain}-cloudfront-cert" }
}

# ── DNS Validation records ────────────────────────────────────
# Both certs produce the same CNAME record for the same domain.
# We merge them and deduplicate by domain_name key, then create
# only one Route 53 record per unique CNAME.
locals {
  # Collect all DVOs from both certs into one map keyed by domain_name
  all_dvo = merge(
    {
      for dvo in aws_acm_certificate.alb.domain_validation_options :
      dvo.domain_name => dvo
    },
    {
      for dvo in aws_acm_certificate.cloudfront.domain_validation_options :
      dvo.domain_name => dvo
    }
  )
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.all_dvo

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

# ── Wait for ALB cert to be issued ────────────────────────────
resource "aws_acm_certificate_validation" "alb" {
  certificate_arn = aws_acm_certificate.alb.arn
  validation_record_fqdns = [
    for r in aws_route53_record.cert_validation : r.fqdn
  ]
}

# ── Wait for CloudFront cert to be issued ─────────────────────
resource "aws_acm_certificate_validation" "cloudfront" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [
    for r in aws_route53_record.cert_validation : r.fqdn
  ]
}
