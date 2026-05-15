#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Deploying LiteLLM ==="

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
