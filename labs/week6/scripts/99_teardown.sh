#!/usr/bin/env bash
set -uo pipefail

ROOT_APP=root
ARGOCD_NS=argocd

kubectl -n "$ARGOCD_NS" patch application "$ROOT_APP" --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false,"prune":false}}}}' \
  2>/dev/null || true

kubectl -n "$ARGOCD_NS" delete application "$ROOT_APP" \
  --cascade=foreground --ignore-not-found --timeout=10m || true

if kubectl -n "$ARGOCD_NS" get application "$ROOT_APP" >/dev/null 2>&1; then
  kubectl -n "$ARGOCD_NS" patch application "$ROOT_APP" \
    --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' || true
fi

kubectl -n "$ARGOCD_NS" delete applicationset --all --ignore-not-found
kubectl -n "$ARGOCD_NS" delete application --all --cascade=foreground --ignore-not-found
kubectl delete ingress --all --all-namespaces --ignore-not-found
kubectl delete rollout --all --all-namespaces --ignore-not-found

# Remove ExternalSecret finalizers before ESO controller is gone
kubectl get externalsecret --all-namespaces -o name 2>/dev/null | while read -r es; do
  kubectl patch "$es" --type=json \
    -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
done
kubectl delete externalsecret --all --all-namespaces --ignore-not-found

helm -n "$ARGOCD_NS" uninstall argocd || true
helm -n kube-system uninstall aws-load-balancer-controller || true

terraform destroy -auto-approve
