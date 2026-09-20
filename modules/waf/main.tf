# ---------------------------------------------------------------
# WAF – Regional WebACL attached to the ALB via Ingress annotation
#
# Default action : BLOCK everything
# Rule 1         : ALLOW if header "x-cloudfront-secret" matches
#                  the secret value exactly (CloudFront injects it)
# Rule 2         : AWS Managed Common Rule Set (SQLi, XSS, etc.)
#
# The WebACL ARN is passed to the Kubernetes Ingress annotation
# alb.ingress.kubernetes.io/wafv2-acl-arn so the LBC associates
# it to the ALB automatically – no aws_wafv2_web_acl_association
# resource needed (and no drift risk).
# ---------------------------------------------------------------

# Auto-generate a secret if the caller didn't supply one
resource "random_password" "cf_secret" {
  length  = 32
  special = false # alphanumeric only – safe in HTTP headers
}

locals {
  # Use the supplied secret if non-empty, otherwise use the generated one
  cf_secret = var.cloudfront_secret != "" ? var.cloudfront_secret : random_password.cf_secret.result
}

# ── Regional WebACL ───────────────────────────────────────────
resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.project_name}-alb-cf-protection"
  description = "Block all traffic that does not carry the CloudFront secret header"
  scope       = "REGIONAL" # attached to ALB, not CloudFront

  default_action {
    block {}
  }

  # Rule 1 – allow requests carrying the correct CloudFront header
  rule {
    name     = "AllowCloudfrontSecret"
    priority = 1

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        search_string = local.cf_secret

        field_to_match {
          single_header {
            name = "x-cloudfront-secret" # WAF lowercases header names
          }
        }

        text_transformation {
          priority = 0
          type     = "NONE"
        }

        positional_constraint = "EXACTLY"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}AllowCloudfrontSecret"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2 – AWS Managed Common Rule Set (SQLi, XSS, bad inputs)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}AlbWAF"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.project_name}-alb-waf" }
}
