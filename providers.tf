# Default provider – eu-west-1 (Ireland)
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

# us-east-1 alias – required for CloudFront ACM certificate
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

# Kubernetes provider – credentials resolved dynamically after cluster creation
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Helm provider – same dynamic credentials
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# Fetch cluster auth token at plan/apply time
data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}
