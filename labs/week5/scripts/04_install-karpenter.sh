#!/usr/bin/env bash
# Karpenter — Helm 설치 (Pod Identity)
# IAM 역할과 Pod Identity association은 karpenter.tf (terraform-aws-modules/eks/aws//modules/karpenter) 에서 생성됨.
# NodePool / EC2NodeClass 매니페스트는 이 스크립트에서 apply하지 않는다.
# 시나리오 2 진행 중 각 단계에서 kubectl apply 한다.
set -euo pipefail

: "${CLUSTER_NAME:=myeks}"
: "${AWS_REGION:=ap-northeast-2}"

KARPENTER_VERSION="${KARPENTER_VERSION:-1.11.1}"
KARPENTER_QUEUE_NAME="${KARPENTER_QUEUE_NAME:-${CLUSTER_NAME}}"

helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace kube-system \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${KARPENTER_QUEUE_NAME}" \
  --wait

echo ""
echo ">>> Verify:"
kubectl -n kube-system rollout status deploy/karpenter

echo ""
echo ">>> Karpenter CRDs:"
kubectl get crd | grep karpenter

echo ""
echo ">>> NodePool / EC2NodeClass는 시나리오 2에서 apply 합니다."
echo "    manifests/scenario2/10-karpenter-install/ 참고"
