#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Deploying Langfuse ==="

helm repo add langfuse https://langfuse.github.io/langfuse-k8s
helm repo update langfuse

helm upgrade --install langfuse langfuse/langfuse \
  --namespace langfuse --create-namespace \
  --values "$(dirname "$0")/manifests/langfuse-values.yaml" \
  --set langfuse.init.org.name=my-org \
  --set langfuse.init.project.name=my-project \
  --set langfuse.init.project.publicKey="$LANGFUSE_PUBLIC_KEY" \
  --set langfuse.init.project.secretKey="$LANGFUSE_SECRET_KEY" \
  --wait --timeout 10m

echo "=== Langfuse deployed ==="
kubectl get pods -n langfuse
