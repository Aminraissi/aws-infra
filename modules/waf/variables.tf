variable "project_name" {
  type = string
}

variable "cloudfront_secret" {
  description = "Secret header value CloudFront injects. Leave empty to auto-generate."
  type        = string
  sensitive   = true
  default     = ""
}
