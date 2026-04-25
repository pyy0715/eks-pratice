########################
# ArgoCD self-managed install (Helm)
# GitOps Bridge pattern: Terraform installs ArgoCD and seeds the cluster Secret
# with metadata so ArgoCD itself can take over addon management from Git.
########################

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.ArgoCDChartVersion
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode({
    global = {
      domain = "argocd.${var.MyDomain}"
    }
    configs = {
      params = {
        "server.insecure" = true
      }
    }
    server = {
      service = {
        type = "ClusterIP"
      }
    }
  })]

  depends_on = [helm_release.aws_lbc]
}

########################
# In-cluster Secret that ArgoCD treats as a registered cluster.
# metadata/labels hold the GitOps Bridge "addons" map, letting
# ApplicationSets select addons per-cluster without hard-coding.
########################

resource "kubernetes_secret_v1" "in_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name

    labels = {
      "argocd.argoproj.io/secret-type"      = "cluster"
      "enable_argo_rollouts"                = "true"
      "enable_argo_events"                  = "true"
      "enable_argo_workflows"               = "true"
      "enable_argocd_image_updater"         = "true"
      "enable_external_secrets"             = "true"
      "enable_aws_load_balancer_controller" = "true"
    }

    annotations = {
      aws_cluster_name      = module.eks.cluster_name
      aws_region            = var.TargetRegion
      aws_account_id        = data.aws_caller_identity.current.account_id
      aws_vpc_id            = module.vpc.vpc_id
      tenant_onboarding_sqs = aws_sqs_queue.tenant_onboarding.url
      ecr_sample_app_repo   = aws_ecr_repository.sample_app.repository_url
      addons_repo_url       = var.GitOpsRepoURL
      addons_repo_revision  = var.GitOpsRepoRevision
    }
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = {
        insecure = false
      }
    })
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}

########################
# ArgoCD UI exposure via ALB
########################

data "aws_acm_certificate" "wildcard" {
  domain   = "*.${var.MyDomain}"
  statuses = ["ISSUED"]
}

resource "kubernetes_manifest" "argocd_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "argocd-server"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      annotations = {
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTPS = 443 }])
        "alb.ingress.kubernetes.io/certificate-arn"  = data.aws_acm_certificate.wildcard.arn
        "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
        "external-dns.alpha.kubernetes.io/hostname"  = "argocd.${var.MyDomain}"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [{
        host = "argocd.${var.MyDomain}"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "argocd-server"
                port = { number = 80 }
              }
            }
          }]
        }
      }]
    }
  }

  depends_on = [helm_release.argocd, helm_release.aws_lbc]
}
