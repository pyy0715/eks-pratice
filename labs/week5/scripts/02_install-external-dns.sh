#!/usr/bin/env bash
# External-DNS — Helm 설치 (Ingress + Gateway HTTPRoute 동시 감시)
# EKS community addon은 sources 커스터마이징이 불가능하므로 Helm release로 배포.
# Pod Identity association은 Terraform에서 이미 생성됨 (aws_eks_pod_identity_association.external_dns).
set -euo pipefail

: "${MyDomain:?MyDomain is not set. Source 00_env.sh first}"
: "${CLUSTER_NAME:=myeks}"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns 2>/dev/null || true
helm repo update external-dns

# namespace/service account 이름은 iam.tf 의 Pod Identity association과 일치해야 함
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns --create-namespace \
  --set serviceAccount.name=external-dns \
  --set "sources={ingress,gateway-httproute}" \
  --set "domainFilters[0]=${MyDomain}" \
  --set txtOwnerId="${CLUSTER_NAME}" \
  --set policy=sync \
  --set provider=aws

echo ""
echo ">>> Verify:"
kubectl -n external-dns rollout status deploy/external-dns
kubectl -n external-dns logs deploy/external-dns --tail=20 || true
