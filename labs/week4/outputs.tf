########################
# Cluster Outputs
########################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC provider URL (without https://)"
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
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
# Identity Outputs
########################

output "irsa_s3_role_arn" {
  description = "IRSA role ARN for S3 access"
  value       = aws_iam_role.irsa_s3.arn
}

output "pod_identity_s3_role_arn" {
  description = "Pod Identity role ARN for S3 access"
  value       = aws_iam_role.pod_identity_s3.arn
}

output "s3_test_bucket" {
  description = "S3 bucket name for IRSA/Pod Identity testing"
  value       = aws_s3_bucket.test.bucket
}

output "viewer_role_arn" {
  description = "Viewer IAM role ARN for Access Entry demo"
  value       = aws_iam_role.viewer_role.arn
}

output "lbc_irsa_role_arn" {
  description = "LBC IRSA role ARN"
  value       = aws_iam_role.lbc_irsa.arn
}
