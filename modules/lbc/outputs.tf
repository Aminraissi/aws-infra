output "lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.lbc.arn
}

# output "helm_release_status" {
#   description = "Helm release status of the LBC deployment"
#   value       = helm_release.lbc.status
# }
