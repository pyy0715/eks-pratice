########################
# Security Group Setup
########################

resource "aws_security_group" "node_group_sg" {
  name        = "${var.ClusterBaseName}-node-group-sg"
  description = "Security group for EKS Node Group"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.ClusterBaseName}-node-group-sg"
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

  # Authenticator 로그 활성화 — CloudWatch에서 TokenReview 관찰
  enabled_log_types = ["authenticator"]

  # API-only 모드: Access Entry만 사용, ConfigMap 비활성
  authentication_mode = "API"

  # Terraform 실행 주체를 cluster-admin으로 등록
  enable_cluster_creator_admin_permissions = true

  # Access Entry: Viewer 역할
  access_entries = {
    viewer = {
      principal_arn = aws_iam_role.viewer_role.arn
      policy_associations = {
        viewer = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # 단일 node group
  eks_managed_node_groups = {
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
        AmazonSSMManagedInstanceCore                            = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      # IMDSv2 강제, hop_limit=2
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
  }

  # EKS Add-ons
  addons = {
    coredns = {
      most_recent = true
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
    # ExternalDNS: Pod Identity 사용 (node role 대신)
    external-dns = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = aws_iam_role.external_dns_pod_identity.arn
        service_account = "external-dns"
      }]
      configuration_values = jsonencode({
        txtOwnerId = var.ClusterBaseName
        policy     = "sync"
      })
    }
  }

  tags = {
    Environment = "cloudneta-lab"
    Terraform   = "true"
  }
}
