# Hands-on Lab

실습 스크립트는 `labs/week2/` 디렉터리를 참고하세요.

---

## Hands-on: Verify Warm Pool

???+ example "WARM_IP_TARGET=5, MINIMUM_IP_TARGET=10 적용 결과"

    ```bash
    # 현재 vpc-cni 애드온 설정 확인
    eksctl get addon --cluster myeks
    # vpc-cni: {"env":{"MINIMUM_IP_TARGET":"10","WARM_IP_TARGET":"5"}}

    # 결과: Pod 없는 노드에도 최소 10개 IP 확보를 위해 ENI가 사전 연결됨
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done
    ```

    - Pod이 없어도 각 노드에 ENI가 연결되어 최소 10개 IP가 확보됩니다.
    - `TotalIPs`가 `MINIMUM_IP_TARGET` 이상으로 유지되는 것을 확인할 수 있습니다.
    
### 활성화 방법

    ```bash
    # VPC CNI에서 Custom Networking 활성화
    kubectl set env daemonset aws-node -n kube-system \
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true

    # ENIConfig CRD로 Availability Zone별 서브넷/Security Group 지정
    kubectl apply -f - <<EOF
    apiVersion: crd.k8s.amazonaws.com/v1alpha1
    kind: ENIConfig
    metadata:
      name: ap-northeast-2a
    spec:
      subnet: subnet-0123456789abcdef0   # Pod 전용 서브넷
      securityGroups:
        - sg-0123456789abcdef0
    EOF
    ```


## Hands-on: Secondary IP Mode — Pod Limit { #pod-capacity }

### Secondary IP 모드에서 Pod 한계 도달

=== "스케일 아웃 테스트"

    ```bash
    # Deployment 스케일 증가 테스트
    kubectl scale deployment nginx-deployment --replicas=50
    # → 3노드 × 15개 = 45개 가능, 그 이상은 Pending
    ```

=== "Pending 원인 확인"

    ```bash
    # Pending Pod 이벤트 확인
    kubectl describe pod <Pending Pod> | grep Events: -A5
    # Warning  FailedScheduling: Too many pods
    ```

=== "IP 소진 확인"

    ```bash
    # IpamD로 IP 소진 확인
    for i in $N1 $N2 $N3; do
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    # TotalIPs: 15, AssignedIPs: 15  (3노드 모두 IP 고갈)
    ```

---

## Hands-on: Prefix Delegation — More Pods

### Prefix Delegation으로 Pod 수 늘리기

=== "Prefix 할당 확인"

    ```bash
    # Prefix 할당 확인
    aws ec2 describe-instances \
      --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=myeks" \
      --query 'Reservations[*].Instances[].{InstanceId:InstanceId, Prefixes:NetworkInterfaces[].Ipv4Prefixes[]}' | jq
    # "Ipv4Prefix": "192.168.10.16/28"  ← /28 = 16개 IP
    ```

=== "IpamD 상태 확인"

    ```bash
    # Prefix 모드에서 IpamD 상태 (Pod 없어도 IP 더 많이 확보)
    # TotalIPs: 32~33 (t3.medium), AssignedIPs는 maxPods에 따라 제한
    for i in $N1 $N2 $N3; do
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

Prefix Delegation은 ENI 슬롯당 IP 개수를 16배 늘려주지만, maxPods는 kubelet이 독립적으로 관리합니다.
kubelet의 `--max-pods` 값은 CNI 플러그인이 아닌 노드 부트스트랩 시점에 주입되며,
EKS Managed Node Group은 하위 호환성을 위해 Prefix Delegation 활성화 여부와 무관하게 Secondary IP 모드 기준 maxPods를 유지합니다.
IP가 늘었다고 무조건 Pod를 많이 띄우면 노드 CPU/메모리가 과부하될 수 있어, 운영자가 maxPods를 올린 다음에만 고밀도 배치가 이뤄지도록 의도적으로 분리한 설계입니다.

!!! warning "Prefix Delegation does not automatically raise maxPods"
    고밀도 배치를 원하면 maxPods도 함께 올려야 합니다.
    c5.large와 Prefix Delegation을 함께 쓰고 maxPods=110으로 설정하면 노드 1대에 110개 Pod 배치가 가능합니다(TotalIPs: 112, AssignedIPs: 108 — ipamd 실측값).

    AL2023부터는 `nodeadm`의 `NodeConfig`에서 `maxPodsExpression`으로 설정합니다.
    AL2에서 사용하던 `max-pods-calculator.sh`는 AL2 지원 종료에 맞춰 삭제되었습니다. :octicons-issue-closed-16: awslabs/amazon-eks-ami#2651

    Prefix Delegation 설정 방법은 [IP Allocation Modes](./2_ip-modes.md)를 참고하세요.

---

## 실습 체크리스트

### VPC CNI & Pod 네트워킹 ([1_vpc-cni.md](./1_vpc-cni.md), [4_pod-networking.md](./4_pod-networking.md))

- [x] Worker Node 네트워크 기본 정보 확인 (`ip addr`, `ip route`, `iptables`)
- [x] netshoot Pod 배포 후 Pod 간 ping/tcpdump
- [x] 외부 통신 SNAT 확인 (`ipinfo.io/ip` 비교)

### IP 모드 & Pod 수용량 ([2_ip-modes.md](./2_ip-modes.md), [3_pod-capacity.md](./3_pod-capacity.md))

- [x] `WARM_IP_TARGET` / `MINIMUM_IP_TARGET` 설정 변경 적용
- [x] Secondary IP 모드 최대 Pod 한계 도달 실습
- [x] Prefix Delegation 활성화 후 IP 수 비교

### AWS LBC ([6_load-balancer.md](./6_load-balancer.md))

- [x] AWS LBC 설치 + NLB IP 모드 에코 서버 배포
- [x] ALB Ingress + 2048 게임 배포

### ExternalDNS & Gateway API ([7_gateway-dns.md](./7_gateway-dns.md))

- [x] ExternalDNS 설치 + Service 도메인 연동
- [ ] Gateway API HTTPRoute + ExternalDNS 도메인 연동

### 도전 과제

- [ ] Custom Networking 설정
- [ ] Service(NLB) + TLS + ExternalDNS
- [ ] Ingress(ALB) + HTTPS + ExternalDNS

---

## 주요 디버깅 명령어

### IpamD 상태 (IP 할당 현황)

```bash
for i in $N1 $N2 $N3; do
  echo ">> node $i <<"
  ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
done | grep -E 'node|TotalIPs|AssignedIPs'
```

### CNI 로그 확인

```bash
for i in $N1 $N2 $N3; do
  echo ">> node $i <<"
  ssh ec2-user@$i sudo cat /var/log/aws-routed-eni/ipamd.log | jq
done
```

### 네트워크 네임스페이스

```bash
# 현재 호스트의 네트워크 네임스페이스 목록
sudo lsns -t net
```

### SNAT iptables 확인

```bash
sudo iptables -t nat -S | grep 'A AWS-SNAT-CHAIN'
```

### conntrack 확인

```bash
# 메타데이터 주소 제외
sudo conntrack -L -n | grep -v '169.254.169'
```
