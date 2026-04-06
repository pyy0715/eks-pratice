########################
# IAM Policies
########################

# AWS Load Balancer Controller IAM Policy (최신 정책 자동 fetch)
data "http" "aws_lb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_lb_controller_policy" {
  name   = "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy"
  policy = data.http.aws_lb_controller_policy.response_body
}

# External DNS IAM Policy
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

# Cluster Autoscaler IAM Policy
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
