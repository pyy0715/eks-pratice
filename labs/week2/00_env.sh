#!/usr/bin/env bash

if [[ -z "${TF_VAR_MyDomain:-}" ]]; then
  echo "error: TF_VAR_MyDomain not set — check mise.toml" >&2
  return 1
fi

export MyDomain="$TF_VAR_MyDomain"
export SSH_KEY="$HOME/.ssh/${TF_VAR_KeyName}.pem"

export CLUSTER_NAME="myeks"
export AWS_REGION="ap-northeast-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.resourcesVpcConfig.vpcId" --output text)
export MyDnzHostedZoneId=$(aws route53 list-hosted-zones-by-name --dns-name "$MyDomain" --query "HostedZones[0].Id" --output text | sed 's|/hostedzone/||')

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# node public ips (bash/zsh compatible)
read -r N1 N2 N3 N4 _ <<< "$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}')"
export N1="${N1:-}" N2="${N2:-}" N3="${N3:-}" N4="${N4:-}"

echo "CLUSTER_NAME=$CLUSTER_NAME  ACCOUNT_ID=$ACCOUNT_ID  VPC_ID=$VPC_ID"
echo "MyDomain=$MyDomain  MyDnzHostedZoneId=$MyDnzHostedZoneId"
echo "N1=$N1  N2=$N2  N3=$N3  N4(pd-110)=$N4"
