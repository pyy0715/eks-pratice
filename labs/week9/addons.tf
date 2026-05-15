# ---------------------------------------------------------------------------
# EFS CSI Driver
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "efs_csi" {
  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:CreateAccessPoint",
      "elasticfilesystem:DeleteAccessPoint",
      "elasticfilesystem:TagResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "efs_csi" {
  name   = "${var.ClusterBaseName}-efs-csi"
  policy = data.aws_iam_policy_document.efs_csi.json
}

resource "aws_iam_role" "efs_csi" {
  name = "${var.ClusterBaseName}-efs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = aws_iam_policy.efs_csi.arn
}

data "aws_eks_addon_version" "efs_csi" {
  addon_name         = "aws-efs-csi-driver"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "aws-efs-csi-driver"
  addon_version = data.aws_eks_addon_version.efs_csi.version

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi.arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# StorageClasses
# ---------------------------------------------------------------------------
resource "kubernetes_storage_class_v1" "ebs" {
  metadata {
    name = "ebs-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.eks.amazonaws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [module.eks]
}

resource "kubernetes_storage_class_v1" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Delete"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.this.id
    directoryPerms   = "700"
  }

  mount_options = ["iam"]

  depends_on = [aws_eks_addon.efs_csi]
}

# ---------------------------------------------------------------------------
# GPU NodeClass + NodePool
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "gpu_nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"
    metadata = {
      name = "gpu"
    }
    spec = {
      role = module.eks.node_iam_role_name
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = var.ClusterBaseName
        }
      }]
      securityGroupSelectorTerms = [{
        id = module.eks.cluster_primary_security_group_id
      }]
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "gpu_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "gpu"
          }
          requirements = [
            {
              key      = "eks.amazonaws.com/instance-family"
              operator = "In"
              values   = var.gpu_instance_families
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.gpu_capacity_type
            },
          ]
          taints = [{
            key    = "nvidia.com/gpu"
            value  = "true"
            effect = "NoSchedule"
          }]
        }
      }
      limits = {
        "nvidia.com/gpu" = "4"
      }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "30s"
        budgets = [{
          nodes = "100%"
        }]
      }
    }
  })

  depends_on = [kubectl_manifest.gpu_nodeclass]
}

# ---------------------------------------------------------------------------
# Neuron NodeClass + NodePool
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "neuron_nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"
    metadata = {
      name = "neuron"
    }
    spec = {
      role = module.eks.node_iam_role_name
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = var.ClusterBaseName
        }
      }]
      securityGroupSelectorTerms = [{
        id = module.eks.cluster_primary_security_group_id
      }]
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "neuron_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "neuron"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "neuron"
          }
          requirements = [
            {
              key      = "eks.amazonaws.com/instance-family"
              operator = "In"
              values   = var.neuron_instance_families
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.neuron_capacity_type
            },
          ]
          taints = [{
            key    = "aws.amazon.com/neuron"
            value  = "true"
            effect = "NoSchedule"
          }]
        }
      }
      limits = {
        "aws.amazon.com/neuroncore" = "8"
      }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "30s"
        budgets = [{
          nodes = "100%"
        }]
      }
    }
  })

  depends_on = [kubectl_manifest.neuron_nodeclass]
}
