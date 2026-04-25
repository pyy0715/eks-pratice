data "aws_caller_identity" "current" {}

########################
# AWS Load Balancer Controller — Pod Identity
########################

data "http" "aws_lb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_lb_controller_policy" {
  name   = "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy"
  policy = data.http.aws_lb_controller_policy.response_body
}

resource "aws_iam_role" "lbc_pod_identity" {
  name = "${var.ClusterBaseName}-lbc-pod-identity-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc_pod_identity" {
  role       = aws_iam_role.lbc_pod_identity.name
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc_pod_identity.arn
}

########################
# External-DNS — Pod Identity
########################

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

resource "aws_iam_role_policy_attachment" "external_dns_pod_identity" {
  role       = aws_iam_role.external_dns_pod_identity.name
  policy_arn = aws_iam_policy.external_dns_policy.arn
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns_pod_identity.arn
}

########################
# Argo Events — SQS read permission
########################

resource "aws_iam_policy" "argo_events_sqs" {
  name = "${var.ClusterBaseName}ArgoEventsSQSPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      Resource = [aws_sqs_queue.tenant_onboarding.arn]
    }]
  })
}

resource "aws_iam_role" "argo_events_pod_identity" {
  name = "${var.ClusterBaseName}-argo-events-pod-identity-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "argo_events_sqs" {
  role       = aws_iam_role.argo_events_pod_identity.name
  policy_arn = aws_iam_policy.argo_events_sqs.arn
}

resource "aws_eks_pod_identity_association" "argo_events" {
  cluster_name    = module.eks.cluster_name
  namespace       = "argo-events"
  service_account = "argo-events-sa"
  role_arn        = aws_iam_role.argo_events_pod_identity.arn
}

########################
# Argo CD Image Updater — ECR read permission
########################

resource "aws_iam_policy" "image_updater_ecr" {
  name = "${var.ClusterBaseName}ImageUpdaterECRPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken must use Resource: "*" per AWS docs
        Sid      = "GetAuthorizationToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Other ECR read actions are scoped to the lab's sample-app repository
        Sid    = "ReadOnlyRepositoryAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = aws_ecr_repository.sample_app.arn
      }
    ]
  })
}

resource "aws_iam_role" "image_updater_pod_identity" {
  name = "${var.ClusterBaseName}-image-updater-pod-identity-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "image_updater_ecr" {
  role       = aws_iam_role.image_updater_pod_identity.name
  policy_arn = aws_iam_policy.image_updater_ecr.arn
}

resource "aws_eks_pod_identity_association" "image_updater" {
  cluster_name    = module.eks.cluster_name
  namespace       = "argocd"
  service_account = "argocd-image-updater"
  role_arn        = aws_iam_role.image_updater_pod_identity.arn
}

########################
# External Secrets Operator — ECR token generator permission
# ESO uses the ECRAuthorizationToken generator to mint short-lived
# pull credentials, which it materializes into a docker-registry
# secret consumed by image-updater (`pullsecret:argocd/ecr-creds`).
########################

resource "aws_iam_role" "external_secrets_pod_identity" {
  name = "${var.ClusterBaseName}-external-secrets-pod-identity-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets_ecr" {
  role       = aws_iam_role.external_secrets_pod_identity.name
  policy_arn = aws_iam_policy.image_updater_ecr.arn
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets_pod_identity.arn
}
