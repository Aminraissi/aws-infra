variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_id" {
  type = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the EKS module"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix"
  type        = string
}

variable "lbc_chart_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.7.2"
}

variable "fargate_profile_kube_system_id" {
  description = "Fargate profile ID for kube-system – used as depends_on trigger"
  type        = string
}
