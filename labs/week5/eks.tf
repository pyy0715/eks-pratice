########################
# Security Group
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

resource "aws_security_group_rule" "allow_all_vpc" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = [var.VpcBlock]
  security_group_id = aws_security_group.node_group_sg.id
}

########################
# EKS Cluster
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

  enabled_log_types = [
    "api",
    "scheduler",
    "authenticator",
    "controllerManager",
    "audit"
  ]

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.ClusterBaseName
  }

  # 2개의 Managed Node Group
  # ng-1: CAS auto-discovery 대상 (k8s.io/cluster-autoscaler 태그 포함)
  # ng-2: CAS 관리 외 고정 노드 — Controller pod들(LBC, CAS, Karpenter) 배치용
  eks_managed_node_groups = {
    ng_cas = {
      name            = "${var.ClusterBaseName}-ng-cas"
      use_name_prefix = false
      instance_types  = [var.WorkerNodeInstanceType]
      desired_size    = var.WorkerNodeCount
      max_size        = var.WorkerNodeCount + 3
      min_size        = 1
      disk_size       = var.WorkerNodeVolumesize
      subnets         = module.vpc.private_subnets

      vpc_security_group_ids = [aws_security_group.node_group_sg.id]

      iam_role_name            = "${var.ClusterBaseName}-ng-cas"
      iam_role_use_name_prefix = false
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      # CAS auto-discovery 태그는 EKS가 모든 managed NG에 자동으로 붙입니다.
      # ng-system은 min=max=desired=2 로 고정되어 있어 CAS 발견 대상이어도 scale 액션이 일어나지 않습니다.
      # 아래 태그는 명시적 선언으로 의도를 드러내기 위한 것이며 동작상 필수는 아닙니다.
      tags = {
        "k8s.io/cluster-autoscaler/enabled"                = "true"
        "k8s.io/cluster-autoscaler/${var.ClusterBaseName}" = "owned"
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }

      cloudinit_pre_nodeadm = [
        {
          content_type = "text/x-shellscript"
          content      = <<-EOT
            #!/bin/bash
            dnf update -y
            dnf install -y tree bind-utils tcpdump nvme-cli links sysstat ipset htop jq
          EOT
        }
      ]
    }

    # 시스템/Controller 전용 — CAS auto-discovery에서 제외
    ng_system = {
      name            = "${var.ClusterBaseName}-ng-system"
      use_name_prefix = false
      instance_types  = [var.WorkerNodeInstanceType]
      desired_size    = 2
      max_size        = 2
      min_size        = 2
      disk_size       = var.WorkerNodeVolumesize
      subnets         = module.vpc.private_subnets

      vpc_security_group_ids = [aws_security_group.node_group_sg.id]

      iam_role_name            = "${var.ClusterBaseName}-ng-system"
      iam_role_use_name_prefix = false
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      labels = {
        "role" = "system"
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }

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
    eks-pod-identity-agent = {
      most_recent = true
    }
    external-dns = {
      most_recent = true
      configuration_values = jsonencode({
        sources       = ["ingress", "gateway-httproute"]
        domainFilters = [var.MyDomain]
        txtOwnerId    = var.ClusterBaseName
        policy        = "sync"
      })
    }
  }

  tags = {
    Environment = "cloudneta-lab"
    Week        = "5"
    Terraform   = "true"
  }
}
