output "web_acl_arn" {
  description = "WAF WebACL ARN – pass to Ingress annotation wafv2-acl-arn"
  value       = aws_wafv2_web_acl.alb.arn
}

output "web_acl_id" {
  description = "WAF WebACL ID"
  value       = aws_wafv2_web_acl.alb.id
}

output "cloudfront_secret" {
  description = "The secret value CloudFront must send in X-CloudFront-Secret header"
  value       = local.cf_secret
  sensitive   = true
}
