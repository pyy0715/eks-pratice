data "aws_caller_identity" "current" {}

########################
# AWS Load Balancer Controller — Pod Identity
# Gateway API(HTTPRoute, Gateway, GatewayClass) 관리에도 동일 Controller가 사용됨 (v2.14.0+)
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
# EKS addon으로 설치됨 (eks.tf의 cluster_addons)
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
# Cluster Autoscaler — Pod Identity
# scripts/02 에서 Helm 설치
########################

resource "aws_iam_policy" "cas_autoscaling_policy" {
  name = "${var.ClusterBaseName}CASAutoscalingPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role" "cas_pod_identity" {
  name = "${var.ClusterBaseName}-cas-pod-identity-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cas_pod_identity" {
  role       = aws_iam_role.cas_pod_identity.name
  policy_arn = aws_iam_policy.cas_autoscaling_policy.arn
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cas_pod_identity.arn
}
