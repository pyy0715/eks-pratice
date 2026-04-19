########################
# AWS Load Balancer Controller (Helm + IRSA)
# v2.14.0+ 에서 Gateway API(HTTPRoute, Gateway, GatewayClass) GA 지원.
# 동일 Controller 가 ALB Ingress 와 Gateway API 리소스를 동시에 관리.
# Gateway API 를 활성화하는 feature flag 의 정확한 이름은 설치 버전의 공식 문서에서 확인해 values 로 추가:
#   https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/
########################

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lbc_irsa.arn
  }

  depends_on = [module.eks]
}
