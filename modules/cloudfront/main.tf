# ---------------------------------------------------------------
# CloudFront distribution
#
# Origin  : ALB (HTTPS only)
# Secret  : X-CloudFront-Secret header injected on every request
#           WAF on the ALB blocks anything without this header
# Cache   : TTL=0 – dynamic app, no stale responses
# Cert    : ACM us-east-1 (passed in from acm module)
# Alias   : www.raissiamine.click
# ---------------------------------------------------------------

resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Online Boutique – ${var.www_domain}"
  aliases         = [var.www_domain]

  # ── Origin: ALB ─────────────────────────────────────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-origin"

    # Secret header – WAF allows only requests carrying this value
    custom_header {
      name  = "X-CloudFront-Secret"
      value = var.cloudfront_secret
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"    # ALB has ACM cert
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
      origin_keepalive_timeout = 60
    }
  }

  # ── Default Cache Behaviour ──────────────────────────────────
  default_cache_behavior {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    # Allow all HTTP methods (app has POST/PUT for cart, checkout, etc.)
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    # Forward everything to ALB so dynamic app works correctly
    forwarded_values {
      query_string = true

      # Forward Host header so ALB routing rules match the right Ingress
      headers = ["Host", "Origin", "Authorization"]

      cookies {
        forward = "all"
      }
    }

    # TTL = 0 : never cache – every request hits the ALB
    # Increase default_ttl for static asset paths if needed
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # ── TLS / Certificate ────────────────────────────────────────
  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_certificate_arn   # must be us-east-1
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ── Geo Restrictions ─────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = { Name = "${var.www_domain}-cf" }
}
