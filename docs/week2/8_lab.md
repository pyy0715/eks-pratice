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
