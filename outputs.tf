# ---------------------------------------------------------------
# Root outputs – printed after terraform apply
# ---------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "alb_certificate_arn" {
  description = "ACM certificate ARN for the ALB (eu-west-1) – put in ingress annotation"
  value       = module.acm.alb_certificate_arn
}

output "waf_acl_arn" {
  description = "WAF WebACL ARN – already baked into k8s/ingress.yaml"
  value       = module.waf.web_acl_arn
}

output "cloudfront_secret" {
  description = "Secret value injected by CloudFront – do not share"
  value       = module.waf.cloudfront_secret
  sensitive   = true
}

output "ingress_yaml_path" {
  description = "Path to the generated Ingress manifest – apply this after LBC is ready"
  value       = "${path.module}/k8s/ingress.yaml"
}

output "cloudfront_url" {
  description = "CloudFront distribution URL (available after second apply)"
  value       = var.alb_dns_name != "" ? "https://${module.cloudfront[0].distribution_domain_name}" : "Not yet created – set alb_dns_name and re-apply"
}

output "app_url" {
  description = "Final application URL"
  value       = var.alb_dns_name != "" ? "https://${var.www_domain}" : "Not yet created – set alb_dns_name and re-apply"
}

# ── Bedrock Agent Outputs ─────────────────────────────────────
output "assistant_api_url" {
  description = "Product assistant chat API URL"
  value       = module.bedrock_agent.chat_url
}

output "assistant_evaluate_url" {
  description = "LLM-as-a-Judge evaluation URL"
  value       = module.bedrock_agent.evaluate_url
}

output "assistant_dynamodb_table" {
  description = "DynamoDB session memory table"
  value       = module.bedrock_agent.dynamodb_table
}

output "assistant_curl_examples" {
  description = "Example curl commands to test the assistant"
  value       = module.bedrock_agent.chat_example
}
