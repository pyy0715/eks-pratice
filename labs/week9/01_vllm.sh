#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

if [ -z "$HF_TOKEN" ]; then
  echo "ERROR: HF_TOKEN is required. export HF_TOKEN=hf_xxx"
  exit 1
fi

echo "=== Deploying vLLM on Neuron ==="

# 1. Namespace first
kubectl create namespace vllm --dry-run=client -o yaml | kubectl apply -f -

# 2. Secret (Deployment references this via secretKeyRef)
kubectl create secret generic hf-token \
  --namespace vllm \
  --from-literal=token="$HF_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. PVCs + Deployment + Service
kubectl apply -f "$(dirname "$0")/manifests/vllm-deployment.yaml"

echo "Waiting for vLLM pod (first start may take 10+ minutes for Neuron compilation)..."
kubectl rollout status deployment/qwen3-8b-neuron -n vllm --timeout=1200s || true

echo "=== vLLM deployed ==="
kubectl get pods -n vllm -o wide
