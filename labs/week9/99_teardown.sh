#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Tearing down workshop components (reverse order) ==="

echo "Removing Open WebUI..."
helm uninstall openwebui -n openwebui --wait 2>/dev/null || true

echo "Removing LiteLLM..."
helm uninstall litellm -n litellm --wait 2>/dev/null || true

echo "Removing Langfuse..."
helm uninstall langfuse -n langfuse --wait 2>/dev/null || true

echo "Removing vLLM..."
kubectl delete -f "$(dirname "$0")/manifests/vllm-deployment.yaml" --ignore-not-found
kubectl delete secret hf-token -n vllm --ignore-not-found

echo "Deleting namespaces..."
for ns in openwebui litellm langfuse vllm; do
  kubectl delete namespace "$ns" --ignore-not-found
done

echo "Waiting for namespaces to terminate..."
for ns in openwebui litellm langfuse vllm; do
  kubectl wait --for=delete namespace/"$ns" --timeout=120s 2>/dev/null || true
done

echo ""
echo "=== Components removed ==="
echo "GPU/Neuron nodes will scale down automatically (consolidationPolicy: WhenEmpty)."
echo ""
echo "To destroy infrastructure:"
echo "  cd labs/week9 && terraform destroy"
