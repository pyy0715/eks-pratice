# Scenario 1 — Ingress(ALB) → Gateway API Migration

Ingress 기반 ALB를 Gateway API(HTTPRoute, Gateway, GatewayClass)로 옮기는 과정에서 발생하는 두 가지 incident를 재현합니다.

## Pre-flight Check

```bash
source ../../00_env.sh
kubectl get gatewayclass                 # "alb" 등록 확인
kubectl -n external-dns get deploy external-dns
```

## Step 1 — Baseline Ingress

```bash
kubectl apply -f 00-baseline/app-deployment.yaml
envsubst < 00-baseline/ingress.yaml | kubectl apply -f -

# ALB 생성 대기
kubectl -n demo get ingress -w
```

브라우저 또는 curl로 `https://nginx.${MyDomain}` 접근이 정상인지 확인합니다.

## Step 2 — Gateway Installation

ACM에 `*.${MyDomain}` wildcard 인증서가 이미 존재해야 합니다. LBC는 Gateway listener hostname으로 ACM 인증서를 자동 탐색하므로, 별도 Secret 생성이나 certificateRefs 설정이 필요하지 않습니다.

```bash
envsubst < 10-gateway-install/gatewayclass-alb.yaml | kubectl apply -f -
kubectl -n demo get gateway demo-gw -o yaml | yq '.status'
```

Gateway status에 `Accepted: True`와 ALB DNS 주소가 표시되면 정상입니다. `Accepted: False`이면 LBC 로그에서 원인을 확인합니다.

```bash
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50 | grep -i gateway
```

## Step 3 — HTTPRoute Migration

Gateway에 nginx Service를 연결하는 HTTPRoute를 배포합니다. 이 시점부터 Ingress(`nginx.${MyDomain}`)와 Gateway(`gw.${MyDomain}`)가 동시에 트래픽을 받는 공존 구간이 시작됩니다.

```bash
envsubst < 20-migration/httproute.yaml | kubectl apply -f -
```

curl로 `https://gw.${MyDomain}` 접근이 정상인지 확인합니다.

```bash
curl -so /dev/null -w "%{http_code}\n" https://gw.${MyDomain}/
```

## Step 4 — Incident #1: Rolling Update 5xx

preStop과 긴 grace period를 제거한 Deployment로 baseline을 덮어써 rolling update 5xx를 재현합니다.

```bash
kubectl apply -f incidents/01-rolling-update-5xx.yaml

# readiness gate 자동 추가 여부 확인 — 빈 배열이면 미적용
kubectl -n demo get pod -l app=nginx -o jsonpath='{.items[0].spec.readinessGates}'
echo
```

별도 터미널에서 curl 루프를 돌려 둔 상태로 rolling update를 트리거합니다.

```bash
# 터미널 1 — 요청 루프
while true; do curl -so /dev/null -w "%{http_code}\n" https://gw.${MyDomain}/; sleep 0.2; done

# 터미널 2 — rolling update
kubectl -n demo set image deploy/nginx nginx=public.ecr.aws/nginx/nginx:1.28-alpine
kubectl -n demo rollout status deploy/nginx
```

**Expected observation** — rolling update 구간에 curl 출력으로 5xx가 섞여 나옵니다. `readinessGates`가 빈 배열이면 AWS LBC의 자동 추가가 적용되지 않은 상태로, Ingress 시절에 있었을 readiness gate 보호가 현재는 빠져 있음을 확인할 수 있습니다.

**Recovery**

baseline Deployment를 다시 적용해 `preStop` sleep 30초와 `terminationGracePeriodSeconds: 60` 구성을 복원합니다.

```bash
kubectl apply -f 00-baseline/app-deployment.yaml
kubectl -n demo rollout status deploy/nginx
```

복원 후 rolling update를 다시 한 번 트리거했을 때 5xx가 사라지면 해당 구성이 deregister 지연을 흡수하고 있다는 근거가 됩니다.

## Step 5 — Incident #2: Hostname Claim Conflict

baseline Ingress가 `nginx.${MyDomain}`을 claim한 상태에서 같은 hostname을 주장하는 HTTPRoute를 추가합니다.

```bash
envsubst < incidents/02-hostname-conflict.yaml | kubectl apply -f -
```

External-DNS가 두 source를 번갈아 reconcile하면서 A record 값이 Ingress ALB와 Gateway ALB 사이에서 바뀝니다.

```bash
# 반복 조회 — 값이 바뀌어 나옴
for i in 1 2 3 4 5; do dig +short nginx.${MyDomain}; sleep 3; done

# External-DNS 로그에 두 source 가 번갈아 update 하는 흔적 확인
kubectl -n external-dns logs deploy/external-dns --tail=100 | grep -i "nginx\.${MyDomain}"
```

**Expected observation** — dig 결과가 두 ALB DNS 이름 사이에서 교차로 나타납니다. 클라이언트 DNS 캐시 타이밍에 따라 옛 Ingress와 새 Gateway로 요청이 섞여 흘러 예전 버전 응답이 간헐적으로 관측됩니다.

**Recovery**

HTTPRoute의 hostname을 `gw.${MyDomain}`으로 되돌려 source 경합을 제거합니다.

```bash
envsubst < 20-migration/httproute.yaml | kubectl apply -f -
```

Route53에 남은 stale record는 External-DNS가 다음 reconcile에 정리하거나 수동으로 제거합니다.

```bash
aws route53 list-resource-record-sets --hosted-zone-id "$MyDnzHostedZoneId" \
  --query "ResourceRecordSets[?Name=='nginx.${MyDomain}.']"
```

## Step 6 — Canary Shift

Gateway가 안정적으로 트래픽을 받으면 두 번째 backend(`nginx-v2`)를 추가해 weighted routing을 시연합니다.

```bash
# v2 Deployment + Service 배포
kubectl apply -f 30-canary-shift/nginx-v2-deployment.yaml
kubectl -n demo rollout status deploy/nginx-v2

# Weighted HTTPRoute 적용 (nginx 90%, nginx-v2 10%)
envsubst < 30-canary-shift/httproute-weighted.yaml | kubectl apply -f -
# 비율을 단계적으로 조정한 뒤 기존 Ingress를 완전히 삭제합니다.
```

## Related Documents

- `docs/week5/1_common-failures.md` — Running Pods Receiving No Traffic
- `docs/week5/3_availability-and-scale.md` — Zero 5xx on Rolling Update
