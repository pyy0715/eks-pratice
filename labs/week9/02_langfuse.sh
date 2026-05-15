#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Deploying Langfuse ==="

helm repo add langfuse https://langfuse.github.io/langfuse-k8s
helm repo update langfuse

helm upgrade --install langfuse langfuse/langfuse \
  --namespace langfuse --create-namespace \
  --values "$(dirname "$0")/manifests/langfuse-values.yaml" \
  --set "langfuse.additionalEnv[0].name=LANGFUSE_INIT_PROJECT_PUBLIC_KEY" \
  --set "langfuse.additionalEnv[0].value=$LANGFUSE_PUBLIC_KEY" \
  --set "langfuse.additionalEnv[1].name=LANGFUSE_INIT_PROJECT_SECRET_KEY" \
  --set "langfuse.additionalEnv[1].value=$LANGFUSE_SECRET_KEY" \
  --set "langfuse.additionalEnv[2].name=LANGFUSE_INIT_USER_EMAIL" \
  --set "langfuse.additionalEnv[2].value=admin@example.com" \
  --set "langfuse.additionalEnv[3].name=LANGFUSE_INIT_USER_PASSWORD" \
  --set "langfuse.additionalEnv[3].value=Pass@123" \
  --set "langfuse.additionalEnv[4].name=LANGFUSE_INIT_ORG_ID" \
  --set "langfuse.additionalEnv[4].value=my-org" \
  --set "langfuse.additionalEnv[5].name=LANGFUSE_INIT_PROJECT_ID" \
  --set "langfuse.additionalEnv[5].value=my-project" \
  --wait --timeout 10m

echo "=== Langfuse deployed ==="
kubectl get pods -n langfuse
