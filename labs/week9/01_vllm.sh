#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Deploying vLLM on Neuron ==="

kubectl create namespace vllm --dry-run=client -o yaml | kubectl apply -f -

# HuggingFace token secret
kubectl create secret generic hf-token \
  --namespace vllm \
  --from-literal=token="$HF_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# vLLM Namespace + PVCs + Deployment + Service
kubectl apply -f "$(dirname "$0")/manifests/vllm-deployment.yaml"

echo "Waiting for vLLM pod (first start may take 10+ minutes for Neuron compilation)..."
kubectl rollout status deployment/qwen3-8b-neuron -n vllm --timeout=1200s || true

echo "=== vLLM deployed ==="
kubectl get pods -n vllm -o wide
