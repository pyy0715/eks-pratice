########################
# EKS-optimized AMI
########################

data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.KubernetesVersion}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

########################
# Security Group Setup #
########################

resource "aws_security_group" "node_group_sg" {
  name        = "${var.ClusterBaseName}-node-group-sg"
  description = "Security group for EKS Node Group"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.ClusterBaseName}-node-group-sg"
  }
}

resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.ssh_access_cidr]
  security_group_id = aws_security_group.node_group_sg.id
}


########################
# EKS
########################

# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.ClusterBaseName
  kubernetes_version = var.KubernetesVersion

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  endpoint_public_access       = var.endpoint_public_access
  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access_cidrs = (var.endpoint_public_access && var.endpoint_private_access) ? [var.ssh_access_cidr] : null

  # controlplane log
  enabled_log_types = []

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    default = {
      name                   = "${var.ClusterBaseName}-node-group"
      use_name_prefix        = false
      instance_types         = [var.WorkerNodeInstanceType]
      desired_size           = var.WorkerNodeCount
      max_size               = var.WorkerNodeCount + 2
      min_size               = var.WorkerNodeCount - 1
      disk_size              = var.WorkerNodeVolumesize
      subnets                = module.vpc.public_subnets
      key_name               = var.KeyName
      vpc_security_group_ids = [aws_security_group.node_group_sg.id]

      # AL2023 전용 userdata 주입
      cloudinit_pre_nodeadm = [
        {
          content_type = "text/x-shellscript"
          content      = <<-EOT
            #!/bin/bash
            echo "Starting custom initialization..."
            dnf update -y
            dnf install -y tree bind-utils
            echo "Custom initialization completed."
          EOT
        }
      ]
    }

    # Prefix Delegation + maxPods=110 도전과제 노드 그룹
    # Custom AMI로 지정해야 EKS가 maxPods를 덮어쓰지 않음 (3_pod-capacity.md 참조)
    pd-110 = {
      name                   = "${var.ClusterBaseName}-pd-110"
      use_name_prefix        = false
      instance_types         = [var.WorkerNodeInstanceType]
      desired_size           = 1
      max_size               = 2
      min_size               = 1
      disk_size              = var.WorkerNodeVolumesize
      subnets                = module.vpc.public_subnets
      key_name               = var.KeyName
      vpc_security_group_ids = [aws_security_group.node_group_sg.id]

      # SSM Parameter로 조회한 EKS-optimized AMI를 명시 지정 → Custom AMI 취급
      ami_id                     = data.aws_ssm_parameter.eks_ami.value
      ami_type                   = "AL2023_x86_64_STANDARD"
      enable_bootstrap_user_data = true

      cloudinit_pre_nodeadm = [
        {
          content_type = "text/x-shellscript"
          content      = <<-EOT
            #!/bin/bash
            dnf update -y
            dnf install -y tree bind-utils
          EOT
        },
        {
          # nodeadm NodeConfig로 maxPods 명시 설정
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  maxPods: 110
          EOT
        }
      ]

      # 기본 워크로드가 이 노드에 배치되지 않도록 격리
      taints = {
        challenge = {
          key    = "challenge"
          value  = "pd-110"
          effect = "NO_SCHEDULE"
        }
      }

      labels = {
        "challenge" = "pd-110"
      }
    }
  }

  # add-on
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
      # Prefix Delegation 활성화 (2_ip-modes.md 참조)
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  tags = {
    Environment = "cloudneta-lab"
    Terraform   = "true"
  }
}

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  count      = var.endpoint_public_access ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMRoleForInstancesQuickSetup"
  role       = module.eks.eks_managed_node_groups["default"].iam_role_name
}
