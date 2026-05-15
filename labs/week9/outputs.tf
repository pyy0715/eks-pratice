output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "efs_file_system_id" {
  value = aws_efs_file_system.this.id
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.TargetRegion} --name ${module.eks.cluster_name}"
}
