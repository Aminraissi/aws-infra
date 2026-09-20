output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_ca" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  # Strip the https:// prefix – used for building IAM condition keys
  value = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "fargate_profile_kube_system_id" {
  value = aws_eks_fargate_profile.kube_system.id
}

output "fargate_profile_app_id" {
  value = aws_eks_fargate_profile.app.id
}
