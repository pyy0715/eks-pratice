########################
# VPC
########################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>6.5"

  name = "${var.ClusterBaseName}-VPC"
  cidr = var.VpcBlock
  azs  = var.availability_zones

  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnets  = var.public_subnet_blocks
  private_subnets = var.private_subnet_blocks

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  manage_default_network_acl = false

  map_public_ip_on_launch = true

  igw_tags = {
    "Name" = "${var.ClusterBaseName}-IGW"
  }

  public_subnet_tags = {
    "Name"                   = "${var.ClusterBaseName}-PublicSubnet"
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "Name"                            = "${var.ClusterBaseName}-PrivateSubnet"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.ClusterBaseName
  }

  tags = {
    "Environment" = "cloudneta-lab"
    "Week"        = "5"
  }
}
