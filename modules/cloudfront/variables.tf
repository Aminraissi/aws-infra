variable "www_domain" {
  type = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB created by the LBC (from kubectl get ingress)"
  type        = string
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  type        = string
}

variable "cloudfront_secret" {
  description = "Secret value injected into X-CloudFront-Secret header"
  type        = string
  sensitive   = true
}
