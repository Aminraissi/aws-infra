output "alb_certificate_arn" {
  description = "ACM certificate ARN for the ALB (eu-west-1)"
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (us-east-1)"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "hosted_zone_id" {
  description = "Route 53 hosted zone ID (re-exported for other modules)"
  value       = data.aws_route53_zone.main.zone_id
}
