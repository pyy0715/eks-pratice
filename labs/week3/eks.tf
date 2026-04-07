########################
# Security Group Setup
########################

resource "aws_security_group" "node_group_sg" {
  name        = "${var.ClusterBaseName}-node-group-sg"
  description = "Security group for EKS Node Group"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name                     = "${var.ClusterBaseName}-node-group-sg"
    "karpenter.sh/discovery" = var.ClusterBaseName
  }
}

# VPC 내부 Pod-to-Pod 통신 허용
resource "aws_security_group_rule" "allow_all_vpc" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = [var.VpcBlock]
  security_group_id = aws_security_group.node_group_sg.id
}

########################
# EKS
########################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.ClusterBaseName
  kubernetes_version = var.KubernetesVersion

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  # controlplane log
  enabled_log_types = []

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  # Karpenter가 프로비저닝하는 노드가 올바른 egress 경로(EKS API, ECR 등)를 갖도록
  # 모듈이 생성한 node security group에 discovery 태그를 추가
  # EC2NodeClass.securityGroupSelectorTerms가 이 SG를 선택하게 됨
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.ClusterBaseName
  }

  # EKS Managed Node Group(s)
  eks_managed_node_groups = merge(
    # Default node group (myeks-ng-1)
    {
      default = {
        name            = "${var.ClusterBaseName}-ng-1"
        use_name_prefix = false
        instance_types  = [var.WorkerNodeInstanceType]
        desired_size    = var.WorkerNodeCount
        max_size        = var.WorkerNodeCount + 2
        min_size        = 1
        disk_size       = var.WorkerNodeVolumesize
        subnets         = module.vpc.private_subnets

        vpc_security_group_ids = [aws_security_group.node_group_sg.id]

        iam_role_name            = "${var.ClusterBaseName}-ng-1"
        iam_role_use_name_prefix = false
        iam_role_additional_policies = {
          "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy" = aws_iam_policy.aws_lb_controller_policy.arn
          "${var.ClusterBaseName}ExternalDNSPolicy"               = aws_iam_policy.external_dns_policy.arn
          "${var.ClusterBaseName}CASAutoscalingPolicy"            = aws_iam_policy.cas_autoscaling_policy.arn
          AmazonSSMManagedInstanceCore                            = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        # IMDSv2 강제, hop_limit=2 (파드에서 IMDS 접근 허용)
        metadata_options = {
          http_endpoint               = "enabled"
          http_tokens                 = "required"
          http_put_response_hop_limit = 2
        }

        # AL2023 전용 userdata 주입
        cloudinit_pre_nodeadm = [
          {
            content_type = "text/x-shellscript"
            content      = <<-EOT
              #!/bin/bash
              echo "Starting custom initialization..."
              dnf update -y
              dnf install -y tree bind-utils tcpdump nvme-cli links sysstat ipset htop
              echo "Custom initialization completed."
            EOT
          }
        ]
      }
    },

    # ARM/Graviton node group (myeks-ng-2) — conditional
    var.enable_ng2_arm ? {
      secondary = {
        name            = "${var.ClusterBaseName}-ng-2"
        use_name_prefix = false
        ami_type        = "AL2023_ARM_64_STANDARD"
        instance_types  = ["t4g.medium"]
        desired_size    = 1
        max_size        = 1
        min_size        = 1
        disk_size       = var.WorkerNodeVolumesize
        subnets         = module.vpc.private_subnets

        vpc_security_group_ids = [aws_security_group.node_group_sg.id]

        iam_role_name            = "${var.ClusterBaseName}-ng-2"
        iam_role_use_name_prefix = false
        iam_role_additional_policies = {
          "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy" = aws_iam_policy.aws_lb_controller_policy.arn
          "${var.ClusterBaseName}ExternalDNSPolicy"               = aws_iam_policy.external_dns_policy.arn
          AmazonSSMManagedInstanceCore                            = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        metadata_options = {
          http_endpoint               = "enabled"
          http_tokens                 = "required"
          http_put_response_hop_limit = 2
        }

        labels = {
          tier = "secondary"
        }

        taints = {
          frontend = {
            key    = "cpuarch"
            value  = "arm64"
            effect = "NO_EXECUTE"
          }
        }

        cloudinit_pre_nodeadm = [
          {
            content_type = "text/x-shellscript"
            content      = <<-EOT
              #!/bin/bash
              echo "Starting custom initialization..."
              dnf update -y
              dnf install -y tree bind-utils tcpdump nvme-cli links sysstat ipset htop
              echo "Custom initialization completed."
            EOT
          }
        ]
      }
    } : {},

    # Spot instances node group (myeks-ng-3) — conditional
    var.enable_ng3_spot ? {
      third = {
        name            = "${var.ClusterBaseName}-ng-3"
        use_name_prefix = false
        ami_type        = "AL2023_x86_64_STANDARD"
        capacity_type   = "SPOT"
        instance_types  = ["c5a.large", "c6a.large", "t3a.large", "t3a.medium"]
        desired_size    = 1
        max_size        = 1
        min_size        = 1
        disk_size       = var.WorkerNodeVolumesize
        subnets         = module.vpc.private_subnets

        vpc_security_group_ids = [aws_security_group.node_group_sg.id]

        iam_role_name            = "${var.ClusterBaseName}-ng-3"
        iam_role_use_name_prefix = false
        iam_role_additional_policies = {
          "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy" = aws_iam_policy.aws_lb_controller_policy.arn
          "${var.ClusterBaseName}ExternalDNSPolicy"               = aws_iam_policy.external_dns_policy.arn
          AmazonSSMManagedInstanceCore                            = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        metadata_options = {
          http_endpoint               = "enabled"
          http_tokens                 = "required"
          http_put_response_hop_limit = 2
        }

        labels = {
          tier = "third"
        }

        cloudinit_pre_nodeadm = [
          {
            content_type = "text/x-shellscript"
            content      = <<-EOT
              #!/bin/bash
              echo "Starting custom initialization..."
              dnf update -y
              dnf install -y tree bind-utils tcpdump nvme-cli links sysstat ipset htop
              echo "Custom initialization completed."
            EOT
          }
        ]
      }
    } : {}
  )

  # EKS Add-ons
  addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        autoScaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 10
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    metrics-server = {
      most_recent = true
    }
    external-dns = {
      most_recent = true
      configuration_values = jsonencode({
        txtOwnerId = var.ClusterBaseName
        policy     = "sync"
      })
    }
    # Karpenter controller가 Pod Identity로 AWS API를 호출하려면 필요
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  tags = {
    Environment = "cloudneta-lab"
    Terraform   = "true"
  }
}
