#!/usr/bin/env bash
# Week 9 - GenAI on EKS environment variables

export AWS_REGION="${AWS_REGION:-us-east-2}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-genai-eks}"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# HuggingFace token (required for model download)
export HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN before running}"

# LiteLLM
export LITELLM_API_KEY="${LITELLM_API_KEY:-sk-1234}"

# Langfuse
export LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY:-lf_pk_1234567890}"
export LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY:-lf_sk_1234567890}"

# kubeconfig
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
