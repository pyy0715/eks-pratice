#!/usr/bin/env bash

# set -euo pipefail

export MyDomain="${TF_VAR_MyDomain:?TF_VAR_MyDomain is not set. Check mise.toml}"
export CLUSTER_NAME="myeks"
export AWS_REGION="ap-northeast-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Identity-specific exports
export IRSA_S3_ROLE_ARN=$(terraform output -raw irsa_s3_role_arn)
export POD_IDENTITY_S3_ROLE_ARN=$(terraform output -raw pod_identity_s3_role_arn)
export S3_BUCKET=$(terraform output -raw s3_test_bucket)
export VIEWER_ROLE_ARN=$(terraform output -raw viewer_role_arn)
export LBC_IRSA_ROLE_ARN=$(terraform output -raw lbc_irsa_role_arn)
export OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.identity.oidc.issuer" --output text)

echo "============================================"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo "S3_BUCKET=$S3_BUCKET"
echo "IRSA_S3_ROLE_ARN=$IRSA_S3_ROLE_ARN"
echo "POD_IDENTITY_S3_ROLE_ARN=$POD_IDENTITY_S3_ROLE_ARN"
echo "VIEWER_ROLE_ARN=$VIEWER_ROLE_ARN"
echo "LBC_IRSA_ROLE_ARN=$LBC_IRSA_ROLE_ARN"
echo "OIDC_ISSUER=$OIDC_ISSUER"
echo "============================================"

# SSM managed instances
echo ""
echo "--- SSM Managed Instances ---"
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].{InstanceId:InstanceId, Status:PingStatus, OS:PlatformName}" \
  --output table 2>/dev/null || echo "(No SSM instances found)"
