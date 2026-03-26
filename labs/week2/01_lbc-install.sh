#!/bin/bash
# AWS Load Balancer Controller 설치 (IRSA + Helm)
# 사전 조건: source labs/week2/00_env.sh 실행 완료
# 참고: docs/week2/6_load-balancer.md — Installing AWS LBC via IRSA

set -euo pipefail

echo ">>> [1/4] IAM Policy 다운로드"
curl -so /tmp/aws_lb_controller_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json

echo ">>> [2/4] IAM Policy 생성"
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/aws_lb_controller_policy.json \
  2>/dev/null || echo "Policy already exists, skipping..."

echo ">>> [3/4] IRSA 생성 (kube-system/aws-load-balancer-controller)"
eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --override-existing-serviceaccounts \
  --approve

echo ">>> [4/4] Helm 설치"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.create=false \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID"

echo ">>> LBC 설치 완료. Pod 상태 확인:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
