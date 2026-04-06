#!/usr/bin/env bash

# set -euo pipefail

export MyDomain="${TF_VAR_MyDomain:?TF_VAR_MyDomain is not set. Check mise.toml}"
export CLUSTER_NAME="myeks"
export AWS_REGION="ap-northeast-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)
export MyDnzHostedZoneId=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$MyDomain" --query "HostedZones[0].Id" --output text | sed 's|/hostedzone/||')
export CERT_ARN=$(aws acm list-certificates \
  --query 'CertificateSummaryList[].CertificateArn[]' --output text)

echo "============================================"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo "VPC_ID=$VPC_ID"
echo "MyDomain=$MyDomain"
echo "CERT_ARN=$CERT_ARN"
echo "============================================"

# SSM managed instances
echo ""
echo "--- SSM Managed Instances ---"
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].{InstanceId:InstanceId, Status:PingStatus, OS:PlatformName}" \
  --output table 2>/dev/null || echo "(No SSM instances found)"
