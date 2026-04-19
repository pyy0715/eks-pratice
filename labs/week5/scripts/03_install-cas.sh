#!/usr/bin/env bash
# Cluster Autoscaler — Helm 설치 (Pod Identity)
# 노드 그룹 auto-discovery 대상은 eks.tf 의 ng_cas (k8s.io/cluster-autoscaler/enabled 태그).
# Pod Identity association은 iam.tf 에서 이미 생성됨 (kube-system/cluster-autoscaler).
set -euo pipefail

: "${CLUSTER_NAME:=myeks}"
: "${AWS_REGION:=ap-northeast-2}"

helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo update autoscaler

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName="${CLUSTER_NAME}" \
  --set awsRegion="${AWS_REGION}" \
  --set rbac.serviceAccount.name=cluster-autoscaler

echo ""
echo ">>> Verify:"
kubectl -n kube-system rollout status deploy/cluster-autoscaler-aws-cluster-autoscaler
kubectl -n kube-system logs deploy/cluster-autoscaler-aws-cluster-autoscaler --tail=20 || true

echo ""
echo ">>> Discovered ASGs (check '${CLUSTER_NAME}-ng-cas' only — system NG should NOT be discovered):"
kubectl -n kube-system logs deploy/cluster-autoscaler-aws-cluster-autoscaler \
  --tail=200 | grep -i "auto-discovery\|found.*asg" || true
