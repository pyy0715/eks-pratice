#!/usr/bin/env bash
# AWS Load Balancer Controller — Helm install (EC2 Instance Profile 방식)
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-myeks}"

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --version 3.1.0 \
  --set clusterName="$CLUSTER_NAME"

echo ""
echo ">>> AWS Load Balancer Controller installed."
echo ">>> Verifying pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
