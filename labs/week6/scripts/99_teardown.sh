#!/usr/bin/env bash
set -uo pipefail

# Delete ArgoCD-owned resources that create out-of-cluster AWS infrastructure
# (ALB, target groups) before running terraform destroy, otherwise Terraform
# cannot remove the VPC/subnets that the ALB still references.

kubectl delete applicationset --all -n argocd --ignore-not-found
kubectl delete application --all -n argocd --cascade=foreground --ignore-not-found
kubectl delete ingress --all --all-namespaces --ignore-not-found
kubectl delete rollout --all --all-namespaces --ignore-not-found

helm -n argocd uninstall argocd || true
helm -n kube-system uninstall aws-load-balancer-controller || true

terraform destroy -auto-approve
