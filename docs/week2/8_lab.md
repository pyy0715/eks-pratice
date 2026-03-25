# Hands-on Lab

실습 스크립트와 매니페스트는 `labs/week2/` 디렉터리를 참고하세요.

---

## Environment Setup

모든 실습에서 공통으로 사용하는 환경 변수를 설정합니다. `N1`/`N2`/`N3`(노드 IP), `VPC_ID`, `ACCOUNT_ID` 등이 자동으로 추출됩니다.

```bash
source labs/week2/00_env.sh
```

`MyDomain`과 `MyDnzHostedZoneId`는 `00_env.sh`에서 직접 수정하세요.

---

## Hands-on: Warm Pool Tuning

[VPC CNI Architecture](./1_vpc-cni.md#warm-pool-environment-variables)에서 각 환경 변수의 동작 원리를 먼저 확인하세요.

=== "현재 상태 확인"

    ```bash
    # vpc-cni 애드온 현재 설정 확인
    eksctl get addon --cluster $CLUSTER_NAME -o json | jq '.[] | select(.Name=="vpc-cni") | .ConfigurationValues'

    # 각 노드의 ipamd 상태 (TotalIPs, AssignedIPs)
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

=== "설정 변경"

    ```bash
    aws eks update-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name vpc-cni \
      --configuration-values '{"env":{"WARM_IP_TARGET":"5","MINIMUM_IP_TARGET":"10"}}' \
      --resolve-conflicts OVERWRITE

    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni
    ```

=== "적용 결과 확인"

    ```bash
    # TotalIPs가 MINIMUM_IP_TARGET(10) 이상으로 유지되는지 확인
    # Pod이 없어도 각 노드에 최소 10개 IP가 확보됩니다.
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

---

## Hands-on: Pod Networking & SNAT

[Pod Networking](./4_pod-networking.md)에서 veth pair, policy routing, SNAT의 동작 원리를 먼저 확인하세요.

=== "Node Network"

    ```bash
    for i in $N1 $N2 $N3; do
      echo "======== node $i ========"
      ssh ec2-user@$i ip addr show
      ssh ec2-user@$i ip route show
      ssh ec2-user@$i ip rule show
      ssh ec2-user@$i ip link show type veth   # Pod ↔ Host veth pair
    done
    ```

=== "Pod Namespace"

    ```bash
    kubectl run netshoot --image=nicolaka/netshoot -- sleep infinity
    kubectl wait pod netshoot --for=condition=Ready --timeout=60s

    # /32 주소, 169.254.1.1 default route, 정적 ARP 항목 확인
    kubectl exec netshoot -- ip addr show eth0
    kubectl exec netshoot -- ip route show
    kubectl exec netshoot -- arp -a
    # 예상: (169.254.1.1) at <host_veth_MAC> [ether] PERM on eth0

    # Pod 간 ping
    NGINX_IP=$(kubectl get pod -l app=nginx-deployment -o jsonpath='{.items[0].status.podIP}')
    kubectl exec netshoot -- ping -c 3 $NGINX_IP
    ```

=== "SNAT 확인"

    ```bash
    # Pod 아웃바운드 IP 확인 → 노드 IP와 일치하면 SNAT 동작 중
    kubectl exec netshoot -- curl -s https://ipinfo.io/ip
    ssh ec2-user@$N1 curl -s http://169.254.169.254/latest/meta-data/public-ipv4

    # iptables SNAT 규칙 확인
    ssh ec2-user@$N1 sudo iptables -t nat -S | grep 'A AWS-SNAT-CHAIN'
    ```

---

## Hands-on: Secondary IP Mode — Pod Limit { #pod-capacity }

Secondary IP 모드에서 노드당 Pod 한계에 도달하는 과정을 확인합니다.
IP 소진 공식과 인스턴스 유형별 한도는 [Pod Capacity](./3_pod-capacity.md)를, IP 모드 선택 기준은 [IP Allocation Modes](./2_ip-modes.md)를 참고하세요.

=== "스케일 아웃"

    ```bash
    kubectl create deployment nginx-deployment --image=nginx:1.27 --replicas=3
    kubectl scale deployment nginx-deployment --replicas=50
    # → 3노드 × 15개 = 45개 가능, 그 이상은 Pending
    ```

=== "Pending 원인 확인"

    ```bash
    kubectl describe pod <Pending Pod> | grep Events: -A5
    # Warning  FailedScheduling: Too many pods
    ```

=== "IP 소진 확인"

    ```bash
    for i in $N1 $N2 $N3; do
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    # TotalIPs: 15, AssignedIPs: 15  (3노드 모두 IP 고갈)
    ```

---

## Hands-on: Prefix Delegation — More Pods

Prefix Delegation으로 Pod 수용량을 늘리는 방법을 확인합니다.
동작 원리와 Nitro 인스턴스 요구사항은 [IP Allocation Modes](./2_ip-modes.md#prefix-delegation)를 참고하세요.

```bash
# 활성화 후 롤아웃 완료 대기
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
kubectl rollout status daemonset aws-node -n kube-system

# /28 Prefix 할당 확인
aws ec2 describe-instances \
  --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$CLUSTER_NAME" \
  --query 'Reservations[*].Instances[].{InstanceId:InstanceId, Prefixes:NetworkInterfaces[].Ipv4Prefixes[]}' | jq
# "Ipv4Prefix": "192.168.10.16/28"  ← /28 = 16개 IP

# ipamd 상태 재확인 (TotalIPs 증가 확인, t3.medium 기준 32~33)
for i in $N1 $N2 $N3; do
  echo ">> node $i <<"
  ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
done | grep -E 'node|TotalIPs|AssignedIPs'
```

!!! warning "Prefix Delegation does not automatically raise maxPods"
    IP가 늘어도 kubelet의 `maxPods` 설정은 자동으로 올라가지 않습니다.
    c5.large + Prefix Delegation + `maxPods=110` 조합으로 노드 1대에 110개 Pod 배치가 가능합니다.

    AL2023에서는 `nodeadm` NodeConfig로, AL2에서 쓰던 `max-pods-calculator.sh`는 AL2 지원 종료와 함께 삭제되었습니다. :octicons-issue-closed-16: awslabs/amazon-eks-ami#2651

---

## Hands-on: AWS LBC — NLB IP Mode

NLB Instance Mode와의 차이는 [AWS Load Balancer Controller](./6_load-balancer.md#nlb-mode-comparison)를 참고하세요.

```bash
# 1. AWS LBC 설치 (IAM Policy + IRSA + Helm)
bash labs/week2/01_lbc-install.sh

# 2. NLB IP 모드 에코 서버 배포 (프로비저닝 2-3분 소요)
kubectl apply -f labs/week2/manifests/echo-nlb-ip.yaml
kubectl get svc svc-nlb-ip-type -w

# 3. 100회 요청으로 Pod 분산 확인 (약 50:50)
NLB=$(kubectl get svc svc-nlb-ip-type -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in {1..100}; do curl -s $NLB | grep Hostname; done | sort | uniq -c | sort -nr
```

---

## Hands-on: AWS LBC — ALB Ingress

`TargetGroupBinding`을 통해 ALB와 Kubernetes 리소스의 라이프사이클이 분리되는 원리는 [AWS Load Balancer Controller](./6_load-balancer.md#alb-ingress)를 참고하세요.

```bash
# 2048 게임 배포 (Namespace + Deployment + Service + Ingress)
kubectl apply -f labs/week2/manifests/game-2048.yaml
kubectl get ingress -n game-2048 -w   # ALB 프로비저닝 대기

# ALB가 Pod IP를 직접 타겟으로 등록했는지 확인
kubectl get targetgroupbindings -n game-2048
```

---

## Hands-on: Gateway API — ALB + HTTPRoute

GatewayClass → Gateway → HTTPRoute 계층 구조와 Ingress와의 역할 분리는 [Gateway API & ExternalDNS](./7_gateway-dns.md#gateway-api)를 참고하세요.

```bash
# Gateway API CRD 설치 + LBC feature gate 활성화
bash labs/week2/02_gateway-api.sh
```

```bash
# 리소스 순서대로 적용
kubectl apply -f labs/week2/manifests/lbc-config.yaml        # LoadBalancerConfiguration
kubectl apply -f labs/week2/manifests/gatewayclass-alb.yaml  # GatewayClass
kubectl apply -f labs/week2/manifests/gateway-alb-http.yaml  # Gateway → ALB 생성
kubectl apply -f labs/week2/manifests/tg-config.yaml         # TargetGroupConfiguration

# HTTPRoute: REPLACE_WITH_YOUR_DOMAIN을 실제 도메인으로 교체 후 적용
sed "s/REPLACE_WITH_YOUR_DOMAIN/$MyDomain/g" labs/week2/manifests/httproute.yaml | kubectl apply -f -
```

```bash
# GatewayClass / Gateway 상태 확인
kubectl get gatewayclasses -o wide
kubectl get gateways
# alb-http  aws-alb-internet  k8s-default-albhttp-xxx.elb.amazonaws.com  True
```

---

## Hands-on: ExternalDNS

TXT record 기반 소유권 관리와 `txtOwnerId`의 역할은 [Gateway API & ExternalDNS](./7_gateway-dns.md#externaldns)를 참고하세요.

```bash
# ExternalDNS 설치 (IRSA + Helm)
# 00_env.sh에서 MyDomain, MyDnzHostedZoneId 설정 후 실행
bash labs/week2/03_externaldns.sh

# Service에 도메인 연결 후 Route53 A 레코드 확인 (1-2분 소요)
kubectl annotate service svc-nlb-ip-type \
  "external-dns.alpha.kubernetes.io/hostname=tetris.$MyDomain"

aws route53 list-resource-record-sets \
  --hosted-zone-id "$MyDnzHostedZoneId" \
  --query "ResourceRecordSets[?Type == 'A']" | jq
```

---

## 도전 과제

- [ ] **maxPods=110 노드 그룹** — Prefix Delegation 활성화 후 `labs/week2/challenge-maxpods.tf` 적용, 노드 1대에 110개 Pod 배치 검증.
      참고: [kkamji.net/posts/eks-max-pod-limit](https://kkamji.net/posts/eks-max-pod-limit/)
- [ ] **Service(NLB) + TLS + ExternalDNS** — NLB에 TLS 인증서 연동 및 도메인 자동 등록
- [ ] **Ingress(ALB) + HTTPS + ExternalDNS** — ACM 인증서 + ALB HTTPS 리스너 구성
- [ ] **Gateway API HTTPRoute 고급** — 요청 헤더 조작, 헤더 매칭, Source IP 통제.
      참고: [LBC Gateway API L7 Examples](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/l7gateway/#examples)
- [ ] **CoreDNS 최적화** — `cache`, `forward max_concurrent`, `lameduck` 설정.
      참고: [CoreDNS Monitoring & Optimization](https://devfloor9.github.io/engineering-playbook/docs/infrastructure-optimization/coredns-monitoring-optimization)

---

## 주요 디버깅 명령어

???+ example "IpamD 상태 (IP 할당 현황)"

    ```bash
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

???+ example "CNI 로그"

    ```bash
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i sudo cat /var/log/aws-routed-eni/ipamd.log | jq
    done
    ```

???+ example "네트워크 네임스페이스 / SNAT / conntrack"

    ```bash
    # 네트워크 네임스페이스 목록
    sudo lsns -t net

    # SNAT 규칙
    sudo iptables -t nat -S | grep 'A AWS-SNAT-CHAIN'

    # conntrack (메타데이터 주소 제외)
    sudo conntrack -L -n | grep -v '169.254.169'
    ```
