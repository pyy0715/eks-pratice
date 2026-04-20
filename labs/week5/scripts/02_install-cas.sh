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
echo ">>> CAS auto-discovery 태그가 붙은 ASG 목록:"
# EKS managed node group은 AWS가 기본으로 k8s.io/cluster-autoscaler/* 태그를 ASG에 자동 추가합니다.
# ng-system은 min=max=desired=2로 고정되어 있어 CAS가 발견해도 scale 액션이 발생하지 않습니다.
# 실제 scale 대상은 min<max 로 설정된 ng-cas 뿐입니다.
aws autoscaling describe-auto-scaling-groups --region "${AWS_REGION}" \
  --query "AutoScalingGroups[?Tags[?Key=='k8s.io/cluster-autoscaler/enabled' && Value=='true']].[AutoScalingGroupName, MinSize, MaxSize, DesiredCapacity]" \
  --output table
