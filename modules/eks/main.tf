# ---------------------------------------------------------------
# EKS – Fargate-only cluster
# Includes:
#   - Cluster IAM role
#   - Fargate pod execution role (with CloudWatch Logs permissions)
#   - EKS cluster (public + private endpoint)
#   - Fargate profiles: kube-system, default (app namespace)
#   - OIDC provider for IRSA
#   - CoreDNS patch so it schedules on Fargate
#   - CloudWatch log group for control plane logs
# ---------------------------------------------------------------

# ── Cluster IAM Role ─────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ── Fargate Pod Execution Role ────────────────────────────────
resource "aws_iam_role" "fargate" {
  name = "${var.cluster_name}-fargate-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-fargate-execution-role" }
}

resource "aws_iam_role_policy_attachment" "fargate_execution" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# Allow Fargate pods to push logs to CloudWatch
resource "aws_iam_role_policy" "fargate_cloudwatch" {
  name = "fargate-cloudwatch-logs"
  role = aws_iam_role.fargate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# ── Control Plane Log Group ───────────────────────────────────
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = { Name = "${var.cluster_name}-logs" }
}

# ── Cluster Security Group (additional rules) ─────────────────
resource "aws_security_group" "cluster_additional" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Additional rules for EKS cluster"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-cluster-sg" }
}

# ── EKS Cluster ───────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster_additional.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
    aws_cloudwatch_log_group.eks,
  ]

  tags = { Name = var.cluster_name }
}

# ── OIDC Provider (for IRSA) ──────────────────────────────────
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = { Name = "${var.cluster_name}-oidc" }
}

# ── Fargate Profiles ──────────────────────────────────────────
# kube-system: CoreDNS + AWS LBC pods run here
resource "aws_eks_fargate_profile" "kube_system" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
  }

  tags = { Name = "${var.cluster_name}-fp-kube-system" }
}

# default namespace: all microservices-demo pods run here
resource "aws_eks_fargate_profile" "app" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = var.app_namespace
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = var.app_namespace
  }

  tags = { Name = "${var.cluster_name}-fp-${var.app_namespace}" }
}

# ── CoreDNS Fargate Patch ─────────────────────────────────────
# CoreDNS ships with an annotation that prevents Fargate scheduling.
# This local-exec removes it so CoreDNS can run on Fargate.
# Requires: aws CLI + kubectl on the machine running terraform apply.
# CoreDNS patch skipped - manual patch required after cluster creation
# Run: kubectl patch deployment coredns -n kube-system --type json -p '[{"op":"remove","path":"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
