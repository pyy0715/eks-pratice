#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Deploying Open WebUI ==="

helm repo add open-webui https://open-webui.github.io/helm-charts
helm repo update open-webui

helm upgrade --install openwebui open-webui/open-webui \
  --namespace openwebui --create-namespace \
  --values "$(dirname "$0")/manifests/openwebui-values.yaml" \
  --set "extraEnvVars[0].name=OPENAI_API_KEY" \
  --set "extraEnvVars[0].value=$LITELLM_API_KEY" \
  --wait --timeout 10m

echo "=== Open WebUI deployed ==="
kubectl get pods -n openwebui

echo ""
echo "Access Open WebUI:"
echo "  kubectl port-forward svc/openwebui 8080:80 -n openwebui"
echo "  Then open http://localhost:8080"
