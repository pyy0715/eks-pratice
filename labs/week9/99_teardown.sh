#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Tearing down workshop components (reverse order) ==="

echo "Removing Open WebUI..."
helm uninstall openwebui -n openwebui 2>/dev/null || true
kubectl delete namespace openwebui --wait=false 2>/dev/null || true

echo "Removing LiteLLM..."
helm uninstall litellm -n litellm 2>/dev/null || true
kubectl delete namespace litellm --wait=false 2>/dev/null || true

echo "Removing Langfuse..."
helm uninstall langfuse -n langfuse 2>/dev/null || true
kubectl delete namespace langfuse --wait=false 2>/dev/null || true

echo "Removing vLLM..."
kubectl delete -f "$(dirname "$0")/manifests/vllm-deployment.yaml" 2>/dev/null || true
kubectl delete namespace vllm --wait=false 2>/dev/null || true

echo ""
echo "=== Components removed ==="
echo "To destroy infrastructure: cd labs/week9 && terraform destroy"
