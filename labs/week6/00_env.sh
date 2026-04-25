#!/usr/bin/env bash

export MyDomain="${TF_VAR_MyDomain:?TF_VAR_MyDomain is not set}"
export GitOpsRepoURL="${TF_VAR_GitOpsRepoURL:?TF_VAR_GitOpsRepoURL is not set (ex: https://github.com/you/gitops-lab.git)}"
export CLUSTER_NAME="week6-argocd"
export AWS_REGION="ap-northeast-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export TENANT_SQS_URL=$(terraform output -raw tenant_onboarding_sqs_url 2>/dev/null || echo "")
export SAMPLE_APP_ECR=$(terraform output -raw sample_app_ecr_url 2>/dev/null || echo "")

echo "============================================"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo "MyDomain=$MyDomain"
echo "GitOpsRepoURL=$GitOpsRepoURL"
echo "TENANT_SQS_URL=$TENANT_SQS_URL"
echo "SAMPLE_APP_ECR=$SAMPLE_APP_ECR"
echo "============================================"
