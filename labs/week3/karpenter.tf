########################
# Karpenter
########################


module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  # NodePool 매니페스트(nodepool-*.yaml)의 role 필드와 일치
  node_iam_role_name            = "KarpenterNodeRole-${var.ClusterBaseName}"
  node_iam_role_use_name_prefix = false

  # Pod Identity association 생성 — kube-system/karpenter SA ↔ Controller IAM Role
  create_pod_identity_association = true

  # Karpenter가 프로비저닝하는 노드에 SSM 접근 권한 부여
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "cloudneta-lab"
  }
}
