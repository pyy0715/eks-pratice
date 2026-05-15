module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.ClusterBaseName
  kubernetes_version = var.KubernetesVersion

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  # EKS Auto Mode
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  tags = {
    Environment = "cloudneta-lab"
    Week        = "week9"
    Terraform   = "true"
  }
}
