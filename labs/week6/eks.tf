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

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.ClusterBaseName
  kubernetes_version = var.KubernetesVersion

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  enabled_log_types = ["api", "audit", "authenticator"]

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      name            = "${var.ClusterBaseName}-ng"
      use_name_prefix = false
      instance_types  = [var.WorkerNodeInstanceType]
      desired_size    = var.WorkerNodeCount
      max_size        = var.WorkerNodeCount + 2
      min_size        = 2
      disk_size       = var.WorkerNodeVolumesize
      subnets         = module.vpc.private_subnets

      vpc_security_group_ids = [aws_security_group.node_group_sg.id]

      iam_role_name            = "${var.ClusterBaseName}-ng"
      iam_role_use_name_prefix = false
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }

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
    external-dns = {
      most_recent = true
      configuration_values = jsonencode({
        sources       = ["ingress"]
        domainFilters = [var.MyDomain]
        txtOwnerId    = var.ClusterBaseName
        policy        = "sync"
      })
    }
  }

  tags = {
    Environment = "cloudneta-lab"
    Week        = "6"
    Terraform   = "true"
  }
}
