# ---------------------------------------------------------------
# Root module – wires all child modules together
#
# Apply order (Terraform resolves automatically via depends_on):
#   1. VPC
#   2. EKS + OIDC
#   3. ACM (both certs, DNS validated)
#   4. WAF
#   5. LBC (Helm – needs EKS + OIDC)
#   6. --> MANUAL STEP: kubectl apply manifests + ingress
#   7. CloudFront (needs ALB DNS from step 6)
#   8. DNS (needs CloudFront domain)
# ---------------------------------------------------------------

# ── VPC ──────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  aws_region         = var.aws_region
}

# ── EKS ──────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  app_namespace      = var.app_namespace
}

# ── ACM ──────────────────────────────────────────────────────
module "acm" {
  source = "./modules/acm"

  domain_name = var.domain_name
  www_domain  = var.www_domain

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# ── WAF ──────────────────────────────────────────────────────
module "waf" {
  source = "./modules/waf"

  project_name      = var.project_name
  cloudfront_secret = var.cloudfront_secret
}

# ── AWS Load Balancer Controller ──────────────────────────────
module "lbc" {
  source = "./modules/lbc"

  cluster_name                   = var.cluster_name
  aws_region                     = var.aws_region
  vpc_id                         = module.vpc.vpc_id
  oidc_provider_arn              = module.eks.oidc_provider_arn
  oidc_provider_url              = module.eks.oidc_provider_url
  lbc_chart_version              = var.lbc_version
  fargate_profile_kube_system_id = module.eks.fargate_profile_kube_system_id

  depends_on = [module.eks]
}

# ── Render the Ingress YAML with correct ARNs ─────────────────
# This file is ready to apply after Terraform completes.
# It is NOT applied by Terraform – you apply it manually (see README).
resource "local_file" "ingress" {
  filename = "${path.module}/k8s/ingress.yaml"
  content = templatefile("${path.module}/k8s/ingress.yaml.tpl", {
    app_namespace       = var.app_namespace
    alb_certificate_arn = module.acm.alb_certificate_arn
    waf_acl_arn         = module.waf.web_acl_arn
    health_check_path   = var.health_check_path
    www_domain          = var.www_domain
    app_service_name    = var.app_service_name
    app_service_port    = var.app_service_port
  })
}

# ── CloudFront ────────────────────────────────────────────────
# alb_dns_name is the only value that comes from a manual step.
# After applying the Ingress and waiting for the ALB to provision,
# run: kubectl get ingress online-boutique -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Then set alb_dns_name in terraform.tfvars and re-run terraform apply.
variable "alb_dns_name" {
  description = <<-EOT
    DNS name of the ALB created by the LBC after applying the Ingress.
    Steps:
      1. terraform apply   (creates infra + LBC)
      2. kubectl apply -f k8s/  (deploys app + ingress)
      3. kubectl get ingress online-boutique  (copy ADDRESS)
      4. Set this variable to that ADDRESS
      5. terraform apply   (creates CloudFront + DNS)
  EOT
  type    = string
  default = ""
}

module "cloudfront" {
  source = "./modules/cloudfront"

  # Skip CloudFront until the ALB DNS is known
  count = var.alb_dns_name != "" ? 1 : 0

  www_domain                 = var.www_domain
  alb_dns_name               = var.alb_dns_name
  cloudfront_certificate_arn = module.acm.cloudfront_certificate_arn
  cloudfront_secret          = module.waf.cloudfront_secret
}

# ── Route 53 DNS ──────────────────────────────────────────────
module "dns" {
  source = "./modules/dns"

  count = var.alb_dns_name != "" ? 1 : 0

  domain_name               = var.domain_name
  www_domain                = var.www_domain
  cloudfront_domain_name    = module.cloudfront[0].distribution_domain_name
  cloudfront_hosted_zone_id = module.cloudfront[0].distribution_hosted_zone_id

  depends_on = [module.cloudfront]
}

# ── Bedrock Agent with MCP Server ────────────────────────────
module "bedrock_agent" {
  source = "./modules/bedrock-agent"

  project_name        = var.project_name
  agent_name          = "product-assistant"
  model_id            = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
  judge_model_id      = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
  products_data_path  = "${path.module}/data/products.json"
}
