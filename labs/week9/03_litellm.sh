#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Deploying LiteLLM ==="

# Discover running vLLM models
VLLM_MODELS=""
for pod in $(kubectl get pods -n vllm -l app --no-headers -o custom-columns=":metadata.labels.app" 2>/dev/null | sort -u); do
  VLLM_MODELS="${VLLM_MODELS}  - model_name: vllm/${pod}\n    litellm_params:\n      model: openai/${pod}\n      api_key: fake-key\n      api_base: http://${pod}.vllm:8000/v1\n"
done

if [ -z "$VLLM_MODELS" ]; then
  echo "WARNING: No vLLM models discovered. Run 01_vllm.sh first."
fi

# Check Langfuse
LANGFUSE_CALLBACK=""
if kubectl get pods -n langfuse -l app.kubernetes.io/name=langfuse --no-headers 2>/dev/null | grep -q Running; then
  LANGFUSE_CALLBACK="langfuse"
  echo "Langfuse detected, enabling callback integration"
fi

helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm \
  --namespace litellm --create-namespace \
  --values "$(dirname "$0")/manifests/litellm-values.yaml" \
  --set masterkey="$LITELLM_API_KEY" \
  --set "envVars.LANGFUSE_PUBLIC_KEY=$LANGFUSE_PUBLIC_KEY" \
  --set "envVars.LANGFUSE_SECRET_KEY=$LANGFUSE_SECRET_KEY" \
  --set "envVars.LANGFUSE_HOST=http://langfuse-web.langfuse:3000" \
  --wait --timeout 10m

echo "=== LiteLLM deployed ==="
kubectl get pods -n litellm
