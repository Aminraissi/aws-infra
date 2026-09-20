output "distribution_domain_name" {
  description = "CloudFront distribution domain (e.g. d1234.cloudfront.net)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront hosted zone ID – used for Route 53 alias record"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}
