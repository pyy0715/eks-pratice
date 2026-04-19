#!/usr/bin/env bash
# Gateway API standard CRDs (v1.5.x — AWS LBC v2.14.0+ 가 Gateway API GA 지원)
# AWS Load Balancer Controller는 Terraform에서 이미 Helm으로 설치됨.
# Gateway API 리소스(Gateway, HTTPRoute, GatewayClass)를 LBC가 관리하려면 CRD 선행 설치 필요.
set -euo pipefail

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.5.1}"

echo ">>> Installing Gateway API standard CRDs ${GATEWAY_API_VERSION}"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo ""
echo ">>> Verify CRDs:"
kubectl get crd \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  gatewayclasses.gateway.networking.k8s.io

echo ""
echo ">>> Verify LBC supports Gateway API (controller image >= v2.14.0 required):"
helm -n kube-system list | grep aws-load-balancer-controller

echo ""
echo ">>> Enable Gateway API feature gate on LBC deployment"
# 기존 args를 보존하면서 feature gate 추가 (kubectl set args는 전체 교체 위험)
if ! kubectl -n kube-system get deploy aws-load-balancer-controller \
    -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q "ALBGatewayAPI=true"; then
  kubectl -n kube-system patch deploy aws-load-balancer-controller --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--feature-gates=ALBGatewayAPI=true"}]'
  echo "Feature gate added, waiting for rollout..."
else
  echo "ALBGatewayAPI feature gate already set, skipping"
fi
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller

echo ""
echo ">>> Check GatewayClass registration:"
kubectl get gatewayclass
