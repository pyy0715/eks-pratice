output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "configure_kubectl" {
  description = "Configure kubectl command"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.TargetRegion}"
}

########################
# Karpenter outputs
########################

output "karpenter_controller_iam_role_name" {
  description = "IAM role name assumed by the Karpenter controller pod via Pod Identity"
  value       = module.karpenter.iam_role_name
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name attached to Karpenter-provisioned nodes"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling"
  value       = module.karpenter.queue_name
}

########################
# Pod Identity outputs
########################

output "external_dns_role_arn" {
  description = "IAM role ARN for External-DNS Pod Identity"
  value       = aws_iam_role.external_dns_pod_identity.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler Pod Identity"
  value       = aws_iam_role.cas_pod_identity.arn
}

