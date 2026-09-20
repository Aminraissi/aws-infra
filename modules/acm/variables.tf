variable "domain_name" {
  description = "Root hosted zone domain (e.g. raissiamine.click)"
  type        = string
}

variable "www_domain" {
  description = "Full domain to certify (e.g. www.raissiamine.click)"
  type        = string
}
