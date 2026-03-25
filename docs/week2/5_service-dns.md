# Service, kube-proxy & CoreDNS

kube-proxy와 CoreDNS의 기본 개념은 [Week 1 Add-ons](../week1/3_addons.md)를 참고하세요.
이 페이지에서는 모드별 동작 원리, EKS 설정, 대규모 클러스터 최적화를 중점으로 다룹니다.

---

## Service & kube-proxy

### kube-proxy 동작 모드

=== "iptables (EKS 기본)"

    netfilter iptables 규칙으로 Service IP → Pod IP DNAT을 처리합니다. kube-proxy는 규칙을 설치하는 역할만 하고, 실제 패킷 처리는 커널이 담당합니다. 초기 userspace 모드에서는 kube-proxy가 직접 소켓을 열어 패킷을 받아 Pod로 전달했는데, 패킷마다 커널 ↔ 유저스페이스 전환이 발생해 처리량이 낮았습니다. iptables 모드는 이 전환을 제거해 성능을 크게 개선했고, kube-proxy가 재시작되어도 커널에 설치된 규칙은 그대로 남아 있어 트래픽이 끊기지 않습니다.

    **ClusterIP 트래픽 흐름:**

    ```mermaid
    graph TD
        Src["Source Pod"] -->|"packet to ClusterIP"| PRE["PREROUTING"]
        PRE --> KS["KUBE-SERVICES"]
        KS --> SVC["KUBE-SVC-### (probability split)"]
        SVC -->|"33%"| SEP1["KUBE-SEP-1 → Pod 1"]
        SVC -->|"50%"| SEP2["KUBE-SEP-2 → Pod 2"]
        SVC -->|"100%"| SEP3["KUBE-SEP-3 → Pod 3"]
    ```

    Pod 3개일 때 순차 매칭 확률: 0.333 → 0.500 → 1.000

    ```bash
    # 서비스 체인에서 확률 규칙 확인
    sudo iptables -t nat -L KUBE-SVC-XXXXXXXXX -n
    # KUBE-SEP-AAA  statistic mode random probability 0.33333
    # KUBE-SEP-BBB  statistic mode random probability 0.50000
    # KUBE-SEP-CCC  (확률 없음 — 항상 선택)

    # DNAT 규칙 확인 (목적지를 실제 Pod IP로 교체)
    sudo iptables -t nat -L KUBE-SEP-AAA -n
    # DNAT  tcp  to:10.0.97.30:8080
    ```

    kube-proxy는 DaemonSet으로 모든 노드에서 실행되며 API 서버의 Service·EndpointSlice 변경을 감지해 각 노드의 iptables를 갱신합니다. 모든 노드가 동일한 규칙을 가지므로 NodePort 트래픽은 어느 노드로 들어와도 목적지 Pod에 도달합니다. NodePort는 `KUBE-SERVICES` 뒤에 `KUBE-NODEPORTS` 체인이 추가되며, ClusterIP와 달리 클라이언트 IP가 SNAT됩니다.

    이 전파에는 시간이 걸립니다. VPC CNI가 Pod 삭제 후 30초 동안 IP를 Warm Pool로 반환하지 않는 이유([VPC CNI Architecture](./1_vpc-cni.md#warm-pool-allocation-flow))도 여기에 있습니다. 전파 완료 전에 같은 IP가 새 Pod에 재사용되면 일부 노드의 iptables가 여전히 삭제된 Pod를 가리켜 트래픽이 잘못 전달됩니다.

=== "nftables (v1.31+, 권장)"

    iptables API의 후계자로, nftables API → netfilter subsystem을 사용합니다.
    수만 개 Service 환경에서 iptables보다 빠른 규칙 처리 및 업데이트를 제공합니다.
    Kubernetes 1.31부터 GA이며, IPVS는 v1.35에서 deprecated되어 nftables로 전환이 권장됩니다.

=== "IPVS (deprecated)"

    커널 IPVS + hash table로 낮은 지연, 높은 처리량을 제공했으나 Kubernetes v1.35에서 deprecated되었습니다. IPVS는 hash table 기반 O(1) 조회로 대규모 Service에서 iptables O(n) 탐색보다 빠르지만, Linux 배포판별로 커널 모듈 지원 상태가 달라 유지 관리가 어려웠습니다. nftables가 집합(set) 기반 매칭으로 성능 격차를 좁히면서, 두 경로를 병행 유지하는 복잡도 대비 이점이 줄어 정리되었습니다. nftables로 전환을 권장합니다.

=== "eBPF + XDP"

    BPF 프로그램이 커널 netfilter를 우회하여 최고 성능을 발휘합니다.
    Cilium 같은 별도 CNI 플러그인에서 구현됩니다.
    EKS 기본 VPC CNI 환경에서는 사용하지 않습니다.

---

### iptables 성능 튜닝

수만 개의 Pod/서비스가 있는 대규모 클러스터에서 iptables 규칙 수가 수만 건에 달하면
kube-proxy의 규칙 업데이트가 지연될 수 있습니다. 아래 두 파라미터로 조정합니다.

`minSyncPeriod`
:   iptables 규칙 재동기화 최소 간격. 기본값 `1s` 권장.

    `0s`로 설정하면 Endpoint 변경마다 즉시 재작성합니다. 100개 Pod Deployment를 삭제하면 Pod 하나씩 종료될 때마다 100번 재작성이 발생하고, 수만 건의 규칙이 있는 클러스터에서 한 번 재작성에 수 초가 걸리면 kube-proxy가 계속 뒤처진 상태로 반복 재작성합니다. `1s`로 설정하면 1초 안에 발생한 변경을 한 번에 배치 처리해 재작성 횟수가 크게 줄어듭니다.

    `sync_proxy_rules_duration_seconds` 메트릭이 평균 1초를 초과하면 `minSyncPeriod` 값을 높이는 것을 검토하세요.

`syncPeriod`
:   외부 컴포넌트의 iptables 규칙 간섭 감지 주기. 기본값 사용 권장.
    `1h` 같은 매우 큰 값은 기능 손해가 성능 이득보다 크므로 비권장합니다.

```bash
# 현재 설정 확인
kubectl describe cm -n kube-system kube-proxy-config | grep iptables: -A5
# iptables:
#   minSyncPeriod: 1s
#   syncPeriod: 30s
```

---

## CoreDNS

CoreDNS 기본 소개는 [Week 1 Add-ons](../week1/3_addons.md)를 참고하세요.

### 기본 Corefile 구성

```
.:53 {
    errors
    health { lameduck 5s }   # 종료 전 5초 대기 → DNS 실패 최소화
    ready                     # /ready 엔드포인트 (readinessProbe)
    kubernetes cluster.local in-addr.arpa ip6.arpa {
      pods insecure
      fallthrough in-addr.arpa ip6.arpa
    }
    prometheus :9153
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
```

`lameduck 5s`는 CoreDNS Pod가 SIGTERM을 받은 뒤 실제 종료 전 **5초간 DNS 쿼리에 정상 응답을 유지**하는 Graceful Shutdown 메커니즘입니다. 이 설정이 없으면, CoreDNS가 종료 직후 kube-proxy가 아직 Endpoint를 제거하지 않은 상태에서 일부 Pod가 해당 IP로 DNS 쿼리를 보내 타임아웃이 발생합니다. `lameduck 5s`를 설정하면 CoreDNS는 `/health`를 503으로 반환해 kube-proxy가 Endpoint 제거를 시작하게 하면서도, 5초 동안 DNS 쿼리에는 계속 응답합니다. 이 5초 안에 kube-proxy가 다른 CoreDNS Pod로 라우팅을 전환하므로 롤링 업데이트 중 DNS 실패가 없어집니다.

```
CoreDNS SIGTERM 수신
  ├─ /health → 503 (kube-proxy가 Endpoint 제거 시작)
  ├─ DNS 쿼리 → 계속 정상 응답  (5초간)
  └─ 5초 경과 → 실제 종료
```

대규모 클러스터에서 kube-proxy의 Endpoint 전파 지연이 길 수 있으므로
Pod 수가 많은 클러스터는 `lameduck 30s`로 늘리는 것을 권장합니다.

### 대규모 클러스터 최적화

!!! tip "DNS 응답 시간 최적화"
    DNS 캐싱은 애플리케이션 응답 시간을 크게 단축합니다.
    Pod 수가 많은 클러스터에서는 아래 설정으로 CoreDNS 부하를 줄이세요.

    ```
    cache 30 {
      success 10000 30   # capacity 10k, maxTTL 30s
      denial 2000 10     # negative cache 2k, maxTTL 10s
      prefetch 5 60s     # 동일 질의 5회 이상이면 만료 전 갱신
    }
    forward . /etc/resolv.conf {
      max_concurrent 2000
      prefer_udp
    }
    health { lameduck 30s }
    ```

### EKS CoreDNS 애드온 주요 업데이트

`topologySpreadConstraints`
:   AZ별 균등 분배. EKS 애드온 configuration으로 설정 가능합니다.

`PDB (Pod Disruption Budget)`
:   노드 드레인 시 CoreDNS Pod가 동시에 종료되지 않도록 보호합니다.

`lameduck 5s`
:   롤링 업데이트/재시작 시 DNS 실패를 최소화합니다. 현재 기본값에 포함됩니다.

`readinessProbe`
:   `/health` → `/ready`로 변경되어 더 정확한 준비 상태를 반영합니다.

```bash
# topologySpreadConstraints 적용
aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name coredns \
  --configuration-values 'file://topologySpreadConstraints.yaml'
```
