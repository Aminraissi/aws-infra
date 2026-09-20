# Online Boutique – AWS Infrastructure

**Stack:** EKS Fargate → ALB (AWS LBC) → WAF → CloudFront → Route 53 → `www.raissiamine.click`

---

## Prerequisites

Install these tools before starting:

| Tool | Install |
|---|---|
| Terraform ≥ 1.6 | https://developer.hashicorp.com/terraform/install |
| AWS CLI v2 | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| kubectl | https://kubernetes.io/docs/tasks/tools/ |
| helm | https://helm.sh/docs/intro/install/ |

Configure AWS credentials:
```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=eu-west-1
```

---

## Step 0 – Create the Terraform state backend (one time only)

```bash
aws s3api create-bucket \
  --bucket raissiamine-tfstate \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3api put-bucket-versioning \
  --bucket raissiamine-tfstate \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name raissiamine-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-1
```

---

## Step 1 – Push images to ECR

Your k8s manifests reference short image names (`frontend`, `adservice`, etc.).
Before deploying, push each image to ECR and update the manifests.

```bash
# Create an ECR repo per service (run once)
for svc in frontend adservice cartservice checkoutservice currencyservice \
            emailservice paymentservice productcatalogservice \
            recommendationservice shippingservice; do
  aws ecr create-repository --repository-name $svc --region eu-west-1
done

# Authenticate Docker to ECR
aws ecr get-login-password --region eu-west-1 \
  | docker login --username AWS \
    --password-stdin 142643433528.dkr.ecr.eu-west-1.amazonaws.com

# Build + push each service (run from microservices-demo/src/<service>)
# Example for frontend:
docker build -t frontend .
docker tag frontend:latest 142643433528.dkr.ecr.eu-west-1.amazonaws.com/frontend:latest
docker push 142643433528.dkr.ecr.eu-west-1.amazonaws.com/frontend:latest
```

Then update each manifest image field, e.g.:
```yaml
image: 142643433528.dkr.ecr.eu-west-1.amazonaws.com/frontend:latest
```

Also **remove or patch** the `frontend-external` LoadBalancer service in `frontend.yaml`
(it's a GKE LoadBalancer type that will cause issues on EKS):
```bash
# In kubernetes-manifests/frontend.yaml, delete the frontend-external Service block
# or change its type to ClusterIP
```

---

## Step 2 – First terraform apply (infra + LBC)

```bash
cd infra
terraform init
terraform apply
```

This creates:
- VPC + subnets + VPC endpoints (ECR, S3, STS, Logs, EKS)
- EKS Fargate cluster
- ACM certificates (eu-west-1 + us-east-1) with DNS validation
- WAF WebACL
- AWS Load Balancer Controller via Helm
- Renders `k8s/ingress.yaml` with correct ARNs

⏱ **Expected time: 15–20 minutes** (EKS cluster takes ~10 min, cert validation ~2 min)

After apply, configure kubectl:
```bash
aws eks update-kubeconfig --region eu-west-1 --name online-boutique
kubectl get nodes   # should show Fargate nodes after a pod is scheduled
```

---

## Step 3 – Deploy the application

```bash
# From the microservices-demo root
kubectl apply -f kubernetes-manifests/

# Apply the generated Ingress (created by Terraform in infra/k8s/)
kubectl apply -f infra/k8s/ingress.yaml

# Watch pods come up (Fargate cold start: ~60-90s per pod)
kubectl get pods -w
```

Wait for all pods to reach `Running`:
```bash
kubectl get pods
# NAME                                    READY   STATUS    RESTARTS
# adservice-xxx                           1/1     Running   0
# frontend-xxx                            1/1     Running   0
# ...
```

---

## Step 4 – Get the ALB DNS name

```bash
kubectl get ingress online-boutique
# NAME               CLASS   HOSTS                      ADDRESS                                          PORTS
# online-boutique    alb     www.raissiamine.click      k8s-xxx.eu-west-1.elb.amazonaws.com              80, 443
```

Copy the `ADDRESS` value (the ALB DNS name).

---

## Step 5 – Second terraform apply (CloudFront + DNS)

Add the ALB DNS name to `terraform.tfvars`:
```hcl
alb_dns_name = "k8s-xxx.eu-west-1.elb.amazonaws.com"
```

Then apply again:
```bash
terraform apply
```

This creates:
- CloudFront distribution pointing to the ALB (with secret header)
- Route 53 A + AAAA alias records for `www.raissiamine.click`

⏱ **Expected time: 5–10 minutes** (CloudFront deployment takes a few minutes)

---

## Step 6 – Verify

```bash
# CloudFront URL (should return your app)
curl -I https://www.raissiamine.click

# Direct ALB access should be BLOCKED by WAF (returns 403)
curl -I https://<alb-dns-name>
```

---

## Destroying the stack

> ⚠️ The ALB is created by the LBC (not Terraform). You MUST delete it first,
> otherwise the VPC deletion will hang on a security group dependency.

```bash
# Step 1 – delete the Ingress (this tells LBC to delete the ALB)
kubectl delete ingress online-boutique

# Wait ~30 seconds for the ALB to be deleted, then verify:
aws elbv2 describe-load-balancers --region eu-west-1

# Step 2 – delete the app manifests
kubectl delete -f kubernetes-manifests/

# Step 3 – destroy all Terraform resources
cd infra
terraform destroy
```

---

## Cost breakdown (5 hours)

| Service | ~5h cost |
|---|---|
| EKS Control Plane ($0.10/hr) | $0.50 |
| Fargate pods (varies by manifest requests) | $0.50 – $2.00 |
| VPC Interface Endpoints (5 × $0.01/hr) | $0.25 |
| ALB ($0.008/hr) | $0.04 |
| CloudFront (low demo traffic) | ~$0.00 |
| WAF WebACL + 2 rules | ~$0.05 |
| **Total** | **~$1.50 – $3.00** |

---

## File structure

```
infra/
├── main.tf                        # root – wires all modules
├── variables.tf                   # all input variables
├── outputs.tf                     # printed after apply
├── providers.tf                   # aws (eu-west-1) + aws.us_east_1 + helm + k8s
├── versions.tf                    # pinned provider versions + S3 backend
├── terraform.tfvars               # your values
├── k8s/
│   ├── ingress.yaml.tpl           # Ingress template
│   └── ingress.yaml               # generated by terraform apply (gitignore this)
└── modules/
    ├── vpc/                       # VPC, subnets, VPC endpoints
    ├── eks/                       # EKS cluster, Fargate profiles, OIDC
    ├── acm/                       # 2 ACM certificates + DNS validation
    ├── waf/                       # Regional WAF WebACL
    ├── lbc/                       # AWS LBC IRSA + Helm
    ├── cloudfront/                # CloudFront distribution
    └── dns/                       # Route 53 A + AAAA alias records
```

---

## Rotating the CloudFront secret

If you want to change the secret (e.g. if it was exposed):

1. Update `cloudfront_secret` in `terraform.tfvars`
2. `terraform apply` — updates both WAF rule and CloudFront header simultaneously
3. No downtime — both are updated in the same apply

---

## Modifying ALB attributes via the AWS Console

The Ingress annotations intentionally do NOT include
`alb.ingress.kubernetes.io/load-balancer-attributes`.
This means you can freely modify these in the AWS Console without Terraform overwriting them:

- Access logs (enable → S3 bucket)
- Idle timeout (default 60s)
- Deletion protection
- Cross-zone load balancing
- Desync mitigation mode

Any annotation you add later will be reconciled by LBC on the next Ingress update.
