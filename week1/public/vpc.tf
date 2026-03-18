########################
# VPC
########################

# VPC 모듈: 퍼블릭 및 프라이빗 서브넷을 포함하는 VPC를 생성
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/6.5.0
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>6.5"

  name = "${var.ClusterBaseName}-VPC"
  cidr = var.VpcBlock
  azs  = var.availability_zones

  enable_dns_support   = true # DNS 서버 활성화
  enable_dns_hostnames = true # 인스턴스에 DNS 이름 부여

  public_subnets = var.public_subnet_blocks

  enable_nat_gateway = false

  manage_default_network_acl = false

  map_public_ip_on_launch = true

  igw_tags = {
    "Name" = "${var.ClusterBaseName}-IGW"
  }

  public_subnet_tags = {
    "Name"                   = "${var.ClusterBaseName}-PublicSubnet"
    "kubernetes.io/role/elb" = "1"
  }

  tags = {
    "Environment" = "cloudneta-lab"
  }
}
