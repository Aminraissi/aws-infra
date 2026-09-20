variable "aws_region" {
  description = "Primary AWS region for the EKS cluster and ALB"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "online-boutique"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "online-boutique"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to deploy into (2 minimum)"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "domain_name" {
  description = "Root Route53 hosted zone domain"
  type        = string
  default     = "raissiamine.click"
}

variable "www_domain" {
  description = "Full domain for the application"
  type        = string
  default     = "www.raissiamine.click"
}

variable "app_namespace" {
  description = "Kubernetes namespace where app workloads run"
  type        = string
  default     = "default"
}

variable "app_service_name" {
  description = "Kubernetes Service name for the frontend"
  type        = string
  default     = "frontend"
}

variable "app_service_port" {
  description = "Port of the frontend Kubernetes Service"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Health check path for the ALB target group"
  type        = string
  default     = "/_healthz"
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "142643433528"
}

variable "cloudfront_secret" {
  description = "Secret value injected by CloudFront into X-CloudFront-Secret header. WAF blocks requests without it."
  type        = string
  sensitive   = true
  default     = ""  # leave empty to auto-generate a random value
}

variable "lbc_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.7.2"
}
