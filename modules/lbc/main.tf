# ---------------------------------------------------------------
# AWS Load Balancer Controller (LBC)
#
# 1. IAM policy  – from pinned v2.7.2 JSON file
# 2. IAM role    – IRSA, scoped to the LBC service account
# 3. Helm release – deploys the controller into kube-system
#
# The controller watches Kubernetes Ingress objects and creates
# real ALBs in AWS. It must run BEFORE any Ingress is applied.
# ---------------------------------------------------------------

# ── IAM Policy (pinned to LBC v2.7.2) ────────────────────────
resource "aws_iam_policy" "lbc" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "IAM policy for AWS Load Balancer Controller v2.7.2"
  policy      = file("${path.module}/iam_policy.json")

  tags = { Name = "${var.cluster_name}-lbc-policy" }
}

# ── IRSA Trust Policy ─────────────────────────────────────────
# Allows only the specific LBC service account in kube-system
# to assume this role via the cluster OIDC provider
data "aws_iam_policy_document" "lbc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Scope to exactly the LBC service account
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ── IAM Role ──────────────────────────────────────────────────
resource "aws_iam_role" "lbc" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume_role.json

  tags = { Name = "${var.cluster_name}-lbc-role" }
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# ── Helm Release ──────────────────────────────────────────────
# Disabled due to timeout issues - Install manually after upgrading AWS CLI:
# 
# aws --version  # Must be 2.x
# helm repo add eks https://aws.github.io/eks-charts
# helm repo update
# helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
#   -n kube-system \
#   --set clusterName=online-boutique \
#   --set serviceAccount.create=true \
#   --set serviceAccount.name=aws-load-balancer-controller \
#   --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::142643433528:role/online-boutique-aws-load-balancer-controller \
#   --set region=eu-west-1 \
#   --set vpcId=vpc-0b349d76eea875058 \
#   --set replicaCount=2

/*
resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_chart_version

  # Required settings
  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # Service account – LBC creates it, we annotate it with the IRSA role
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    # IRSA annotation – must escape the dot so Helm treats it as a key
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lbc.arn
  }

  # Run 2 replicas for HA (both on Fargate in kube-system)
  set {
    name  = "replicaCount"
    value = "2"
  }

  # Fargate pods take longer to start – give the webhook time to come up
  timeout          = 900  # Increased to 15 minutes for Fargate
  wait             = true
  wait_for_jobs    = true
  cleanup_on_fail  = true
  replace          = true  # Force replace if exists

  depends_on = [
    aws_iam_role_policy_attachment.lbc,
  ]
}
*/
