# ---------------------------------------------------------------
# DNS – Route 53 A alias record
# www.raissiamine.click → CloudFront distribution
# ---------------------------------------------------------------

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.www_domain
  type    = "A"

  alias {
    name    = var.cloudfront_domain_name
    zone_id = var.cloudfront_hosted_zone_id
    # CloudFront does not support health check evaluation on alias records
    evaluate_target_health = false
  }
}

# IPv6 alias (AAAA) – CloudFront is dual-stack when is_ipv6_enabled = true
resource "aws_route53_record" "www_ipv6" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.www_domain
  type    = "AAAA"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}
