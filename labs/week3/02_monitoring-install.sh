#!/usr/bin/env bash
# Monitoring stack: kube-ops-view + kube-prometheus-stack + Grafana dashboard
set -euo pipefail

MyDomain="${MyDomain:?MyDomain is not set. Run: source 00_env.sh}"
CERT_ARN="${CERT_ARN:?CERT_ARN is not set. Run: source 00_env.sh}"

echo "=== [1/4] kube-ops-view ==="
helm repo add geek-cookbook https://geek-cookbook.github.io/charts/ 2>/dev/null || true
helm repo update geek-cookbook

helm upgrade --install kube-ops-view geek-cookbook/kube-ops-view \
  --version 1.2.2 \
  --set service.main.type=ClusterIP \
  --set env.TZ="Asia/Seoul" \
  --namespace kube-system

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    alb.ingress.kubernetes.io/group.name: study
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
    alb.ingress.kubernetes.io/load-balancer-name: myeks-ingress-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/success-codes: 200-399
    alb.ingress.kubernetes.io/target-type: ip
  name: kubeopsview
  namespace: kube-system
spec:
  ingressClassName: alb
  rules:
  - host: kubeopsview.${MyDomain}
    http:
      paths:
      - backend:
          service:
            name: kube-ops-view
            port:
              number: 8080
        path: /
        pathType: Prefix
EOF

echo "=== [2/4] kube-prometheus-stack ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

cat <<EOT > /tmp/monitor-values.yaml
prometheus:
  additionalRulesForClusterRole:
    - verbs: ["get"]
      apiGroups: ["metrics.eks.amazonaws.com"]
      resources: ["kcm/metrics", "ksh/metrics"]
  prometheusSpec:
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    additionalScrapeConfigs:
      # apiserver metrics
      - job_name: apiserver-metrics
        kubernetes_sd_configs:
        - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels:
            [
              __meta_kubernetes_namespace,
              __meta_kubernetes_service_name,
              __meta_kubernetes_endpoint_port_name,
            ]
          action: keep
          regex: default;kubernetes;https
      # Scheduler metrics
      - job_name: ksh-metrics
        kubernetes_sd_configs:
        - role: endpoints
        metrics_path: /apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels:
            [
              __meta_kubernetes_namespace,
              __meta_kubernetes_service_name,
              __meta_kubernetes_endpoint_port_name,
            ]
          action: keep
          regex: default;kubernetes;https
      # Controller Manager metrics
      - job_name: kcm-metrics
        kubernetes_sd_configs:
        - role: endpoints
        metrics_path: /apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels:
            [
              __meta_kubernetes_namespace,
              __meta_kubernetes_service_name,
              __meta_kubernetes_endpoint_port_name,
            ]
          action: keep
          regex: default;kubernetes;https

  ingress:
    enabled: true
    ingressClassName: alb
    hosts:
      - prometheus.${MyDomain}
    paths:
      - /*
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/success-codes: 200-399
      alb.ingress.kubernetes.io/load-balancer-name: myeks-ingress-alb
      alb.ingress.kubernetes.io/group.name: study
      alb.ingress.kubernetes.io/ssl-redirect: '443'

grafana:
  defaultDashboardsTimezone: Asia/Seoul
  adminPassword: prom-operator

  ingress:
    enabled: true
    ingressClassName: alb
    hosts:
      - grafana.${MyDomain}
    paths:
      - /*
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/success-codes: 200-399
      alb.ingress.kubernetes.io/load-balancer-name: myeks-ingress-alb
      alb.ingress.kubernetes.io/group.name: study
      alb.ingress.kubernetes.io/ssl-redirect: '443'

kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
prometheus-windows-exporter:
  prometheus:
    monitor:
      enabled: false

EOT

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 80.13.3 \
  -f /tmp/monitor-values.yaml \
  --create-namespace --namespace monitoring

echo "=== [3/3] Grafana dashboards ==="
TMPDIR_DASH=$(mktemp -d)

# API Server dashboard (15661)
curl -sO --output-dir "$TMPDIR_DASH" \
  https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/refs/heads/master/dashboards/k8s-system-api-server.json
sed -i'' -e 's/${DS_PROMETHEUS}/prometheus/g' "$TMPDIR_DASH/k8s-system-api-server.json"

# HPA dashboard (17125)
# kube-state-metrics v2.17+ 에서 _labels 메트릭이 기본 비활성화되어 _metadata_generation 으로 대체
curl -s -o "$TMPDIR_DASH/k8s-hpa.json" \
  "https://grafana.com/api/dashboards/17125/revisions/1/download"
sed -i'' -e 's/${DS_PROMETHEUS}/prometheus/g' "$TMPDIR_DASH/k8s-hpa.json"
sed -i'' -e 's/kube_horizontalpodautoscaler_labels/kube_horizontalpodautoscaler_metadata_generation/g' "$TMPDIR_DASH/k8s-hpa.json"

# KEDA dashboard
curl -s -o "$TMPDIR_DASH/keda-dashboard.json" \
  "https://raw.githubusercontent.com/kedacore/keda/main/config/grafana/keda-dashboard.json"
sed -i'' -e 's/${DS_PROMETHEUS}/prometheus/g' "$TMPDIR_DASH/keda-dashboard.json"

kubectl delete configmap grafana-dashboards-custom -n monitoring --ignore-not-found
kubectl create configmap grafana-dashboards-custom \
  --from-file="$TMPDIR_DASH/k8s-system-api-server.json" \
  --from-file="$TMPDIR_DASH/k8s-hpa.json" \
  --from-file="$TMPDIR_DASH/keda-dashboard.json" \
  -n monitoring
kubectl label configmap grafana-dashboards-custom grafana_dashboard="1" -n monitoring
rm -rf "$TMPDIR_DASH"

echo ""
echo "============================================"
echo "Kube Ops View : https://kubeopsview.${MyDomain}/#scale=1.5"
echo "Prometheus    : https://prometheus.${MyDomain}"
echo "Grafana       : https://grafana.${MyDomain}  (admin / prom-operator)"
echo "============================================"
