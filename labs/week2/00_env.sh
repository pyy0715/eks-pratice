#!/usr/bin/env bash
# Week2 공통 환경 변수 설정
# 사용법: source labs/week2/00_env.sh

set -euo pipefail

#----------------------------------------------------
# 사용자 수정 필요 변수
#----------------------------------------------------
export MyDomain="example.com"
export MyDnzHostedZoneId="Z0123456789ABCDEFGHIJ"

#----------------------------------------------------
# 자동 추출 변수
#----------------------------------------------------
export CLUSTER_NAME="myeks"
export AWS_REGION="ap-northeast-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)

# kubeconfig 업데이트
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# 노드 퍼블릭 IP 추출 (bash/zsh 호환)
read -r N1 N2 N3 N4 _ <<< "$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}')"
export N1="${N1:-}"
export N2="${N2:-}"
export N3="${N3:-}"
export N4="${N4:-}"

echo "============================================"
echo "CLUSTER_NAME : $CLUSTER_NAME"
echo "AWS_REGION   : $AWS_REGION"
echo "ACCOUNT_ID   : $ACCOUNT_ID"
echo "VPC_ID       : $VPC_ID"
echo "N1           : $N1"
echo "N2           : $N2"
echo "N3           : $N3"
echo "N4 (pd-110)  : $N4"
echo "MyDomain     : $MyDomain"
echo "============================================"
