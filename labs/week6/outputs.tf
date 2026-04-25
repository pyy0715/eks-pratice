output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Command to configure kubectl for the new cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.TargetRegion}"
}

output "tenant_onboarding_sqs_url" {
  description = "SQS queue URL used by Argo Events for tenant onboarding"
  value       = aws_sqs_queue.tenant_onboarding.url
}

output "sample_app_ecr_url" {
  description = "ECR repository URL for the Image Updater sample app"
  value       = aws_ecr_repository.sample_app.repository_url
}

output "argocd_initial_admin_secret" {
  description = "Command to read the ArgoCD initial admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
