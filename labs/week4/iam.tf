data "aws_caller_identity" "current" {}

########################
# S3 Test Resources
########################

resource "aws_s3_bucket" "test" {
  bucket        = "${var.ClusterBaseName}-iam-test-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Environment = "cloudneta-lab"
  }
}

resource "aws_iam_policy" "s3_test_policy" {
  name = "${var.ClusterBaseName}S3TestPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.test.arn, "${aws_s3_bucket.test.arn}/*"]
    }]
  })
}

########################
# IRSA: S3 Access Role
########################
# raw aws_iam_role — OIDC trust policy를 명시적으로 노출하여 학습 효과 극대화
# terraform-aws-modules/iam 모듈은 trust policy를 추상화하므로 사용하지 않음

resource "aws_iam_role" "irsa_s3" {
  name = "${var.ClusterBaseName}-irsa-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:default:s3-irsa-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_s3" {
  role       = aws_iam_role.irsa_s3.name
  policy_arn = aws_iam_policy.s3_test_policy.arn
}

########################
# Pod Identity: S3 Access Role
########################

resource "aws_iam_role" "pod_identity_s3" {
  name = "${var.ClusterBaseName}-pod-identity-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pod_identity_s3" {
  role       = aws_iam_role.pod_identity_s3.name
  policy_arn = aws_iam_policy.s3_test_policy.arn
}

resource "aws_eks_pod_identity_association" "s3" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "s3-pod-identity-sa"
  role_arn        = aws_iam_role.pod_identity_s3.arn
}

########################
# Pod Identity: ExternalDNS Role
########################

resource "aws_iam_role" "external_dns_pod_identity" {
  name = "${var.ClusterBaseName}-externaldns-pod-identity-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_policy" "external_dns_policy" {
  name = "${var.ClusterBaseName}ExternalDNSPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns_pod_identity" {
  role       = aws_iam_role.external_dns_pod_identity.name
  policy_arn = aws_iam_policy.external_dns_policy.arn
}

########################
# Viewer IAM Role (Access Entry demo)
########################

resource "aws_iam_role" "viewer_role" {
  name = "${var.ClusterBaseName}-viewer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_caller_identity.current.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

########################
# LBC IAM Policy + IRSA Role
########################

data "http" "aws_lb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_lb_controller_policy" {
  name   = "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy"
  policy = data.http.aws_lb_controller_policy.response_body
}

resource "aws_iam_role" "lbc_irsa" {
  name = "${var.ClusterBaseName}-lbc-irsa-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc_irsa" {
  role       = aws_iam_role.lbc_irsa.name
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
}
