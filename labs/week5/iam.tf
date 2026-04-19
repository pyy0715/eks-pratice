data "aws_caller_identity" "current" {}

########################
# AWS Load Balancer Controller — IRSA
# Gateway API(HTTPRoute, Gateway, GatewayClass) 관리에도 동일 Controller가 사용됨 (v2.14.0+)
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

########################
# External-DNS — Pod Identity
# sources={ingress,gateway-httproute} 로 Helm 설치 (scripts/02)
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
# scripts/03 에서 Helm 설치
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
