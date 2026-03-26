#!/bin/bash
# ExternalDNS 설치 (IRSA + Helm)
# 사전 조건: source labs/week2/00_env.sh 실행 완료
# 참고: docs/week2/6_load-balancer.md — ExternalDNS

set -euo pipefail

echo ">>> [1/3] IAM Policy 생성"
aws iam create-policy \
  --policy-name ExternalDNSPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["route53:ChangeResourceRecordSets"],
        "Resource": ["arn:aws:route53:::hostedzone/*"]
      },
      {
        "Effect": "Allow",
        "Action": [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ],
        "Resource": ["*"]
      }
    ]
  }' \
  2>/dev/null || echo "Policy already exists, skipping..."

echo ">>> [2/3] IRSA 생성 (default/external-dns)"
eksctl create iamserviceaccount \
  --name external-dns \
  --namespace default \
  --cluster "$CLUSTER_NAME" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ExternalDNSPolicy" \
  --override-existing-serviceaccounts \
  --approve

echo ">>> [3/3] Helm 설치"
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
helm repo update external-dns

helm install external-dns external-dns/external-dns \
  --set provider.name=aws \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns \
  --set "domainFilters[0]=$MyDomain" \
  --set txtOwnerId="$CLUSTER_NAME" \
  --set policy=upsert-only \
  --set "sources[0]=service" \
  --set "sources[1]=ingress"

echo ">>> ExternalDNS 설치 완료. Pod 상태 확인:"
kubectl get pods -l app.kubernetes.io/name=external-dns
