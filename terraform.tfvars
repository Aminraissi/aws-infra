aws_region         = "eu-west-1"
project_name       = "online-boutique"
cluster_name       = "online-boutique"
cluster_version    = "1.32"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["eu-west-1a", "eu-west-1b"]
domain_name        = "raissiamine.click"
www_domain         = "www.raissiamine.click"
app_namespace      = "default"
app_service_name   = "frontend"
app_service_port   = 80
health_check_path  = "/_healthz"
account_id         = "142643433528"
lbc_version        = "1.7.2"
alb_dns_name       = "k8s-default-onlinebo-b1ff0ef623-2111350026.eu-west-1.elb.amazonaws.com"

# cloudfront_secret – leave empty to auto-generate, or set your own value:
# cloudfront_secret = "my-super-secret-value"
