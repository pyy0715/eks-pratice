########################
# Karpenter (IAM + Pod Identity only)
# Helm chart는 scripts/04_install-karpenter.sh 에서 설치
########################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  node_iam_role_name            = "KarpenterNodeRole-${var.ClusterBaseName}"
  node_iam_role_use_name_prefix = false

  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "cloudneta-lab"
    Week        = "5"
  }
}
