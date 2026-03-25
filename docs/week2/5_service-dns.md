# Service, kube-proxy & CoreDNS

앞서 VPC CNI가 Pod마다 고유한 IP를 부여하고 그 IP로 직접 통신하는 방식을 살펴봤습니다. Pod은 재시작하면 새 IP를 받기 때문에, 클라이언트가 Pod IP를 직접 사용하면 Pod이 재시작될 때마다 연결이 끊깁니다.

Kubernetes는 이 문제를 Service로 해결합니다. Service는 고정된 ClusterIP를 제공하고, kube-proxy가 이 ClusterIP를 현재 실행 중인 Pod IP로 변환합니다. Pod 안에서 IP 대신 `my-svc.my-ns` 같은 이름으로 접근할 수 있는 것은 CoreDNS가 Service 이름을 ClusterIP로 변환해주기 때문입니다.

## Service Discovery

Service는 변하는 Pod IP 집합 앞에 고정된 ClusterIP를 노출합니다. Pod이 교체되어도 ClusterIP는 바뀌지 않으므로 클라이언트는 항상 같은 주소로 요청을 보낼 수 있습니다.

ClusterIP는 실제 네트워크 인터페이스에 바인딩되지 않는 가상 주소입니다. kube-proxy가 이 가상 IP를 실제 Pod IP로 변환하는 iptables 규칙을 모든 노드에 설치합니다. ClusterIP를 목적지로 나가는 패킷은 kube-proxy가 설치한 규칙에 의해 살아있는 Pod IP 중 하나로 DNAT됩니다.

### Proxy Modes

kube-proxy는 다음 방식으로 규칙을 구현합니다. EKS는 기본적으로 iptables를 사용합니다.

=== "iptables (default)"

    kube-proxy는 PREROUTING 단계에서 세 단계 체인으로 ClusterIP 트래픽을 처리합니다. `KUBE-SERVICES`에서 목적지 ClusterIP에 해당하는 Service를 찾고, `KUBE-SVC-*` 체인에서 확률 기반으로 엔드포인트 하나를 고릅니다. 선택된 `KUBE-SEP-*` 체인에서 목적지를 실제 Pod IP로 DNAT합니다.

    ![EKS Service – ClusterIP iptables flow](./assets/EKS%20Service%20ClusterlP.png)
    *Source: [EKS Networking Deep Dive](https://www.youtube.com/watch?v=E49Q3y9wsUo&t=2521s)*

    Pod 3개일 때 확률이 0.333 → 0.500 → 1.000으로 설정되는 이유는, 체인을 순서대로 평가할 때 각 Pod이 균등하게 1/3 확률을 받도록 역산하기 때문입니다.

    DNAT으로 목적지가 실제 Pod IP로 바뀐 패킷은 [Pod-to-Pod Communation](./4_pod-networking.md#pod-to-pod-communication-policy-routing)에서처럼 Policy Routing으로 전달됩니다. kube-proxy의 iptables 규칙이 ClusterIP를 Pod IP로 변환하고, VPC CNI의 Policy Routing이 그 Pod IP를 올바른 인터페이스로 내보내는 역할을 각자 맡습니다.

    kube-proxy는 DaemonSet으로 모든 노드에서 실행되며, API 서버의 Service와 EndpointSlice 변경을 감지해 각 노드의 iptables를 갱신합니다. 모든 노드가 동일한 규칙을 가지므로 NodePort 트래픽은 어느 노드로 들어와도 목적지 Pod에 도달합니다.

    ClusterIP는 VPC 내부에서만 접근 가능한 가상 IP입니다. NodePort는 외부 트래픽을 받기 위해 모든 노드의 특정 포트를 열며, `KUBE-SERVICES` 뒤에 `KUBE-NODEPORTS` 체인이 추가됩니다. SNAT 처리도 서비스 타입에 따라 달라집니다.

    - ClusterIP DNAT의 목적지는 VPC 내부 Pod IP이므로 리턴 패킷이 그대로 돌아올 수 있어 SNAT이 필요 없습니다.
    - NodePort는 외부 클라이언트가 Pod IP를 모르므로 SNAT이 필요합니다.

    이 iptables 규칙 전파에는 시간이 걸립니다. VPC CNI가 Pod 삭제 후 30초 동안 IP를 Warm Pool로 반환하지 않는 이유([VPC CNI Architecture](./1_vpc-cni.md#warm-pool-allocation-flow))도 여기에 있습니다.

    ???+ info "iptables 이전 — userspace 모드"
        초기 userspace 모드에서는 kube-proxy가 직접 소켓을 열어 패킷을 받아 Pod로 전달했습니다. 패킷마다 커널하고 유저스페이스 간 전환이 발생해 처리량이 낮았고, kube-proxy가 재시작되면 트래픽도 잠시 끊겼습니다. iptables 모드는 패킷 처리를 커널에 위임해 이 문제를 해결했습니다.

=== "nftables (v1.33+, recommended)"

    iptables와 동일한 netfilter subsystem을 사용하지만, 규칙 설치에 nftables API를 씁니다. 수만 개 Service 규모에서 규칙 처리와 업데이트 속도가 iptables보다 빠릅니다. Kubernetes 1.29 Alpha → 1.31 Beta를 거쳐 1.33에서 GA가 되었으며, IPVS는 v1.35에서 deprecated(v1.36 제거 예정)되어 nftables로 전환이 권장됩니다.

=== "IPVS (deprecated)"

    커널 IPVS와 hash table을 이용해 낮은 지연, 높은 처리량을 제공했으나 Kubernetes v1.35에서 deprecated되었습니다. hash table 기반 O(1) 조회로 대규모 Service에서 iptables O(n) 탐색보다 빠르지만, Linux 배포판별로 커널 모듈 지원 상태가 달라 유지 관리가 어려웠습니다. nftables의 집합(set) 기반 매칭이 성능 격차를 좁히면서 IPVS를 별도로 유지하는 이점이 줄어 정리되었습니다.

=== "eBPF + XDP"

    BPF 프로그램이 커널 netfilter를 우회해 최고 성능을 발휘합니다. Cilium 같은 별도 CNI 플러그인에서 구현되며, EKS 기본 VPC CNI 환경에서는 사용하지 않습니다.

### iptables Performance Tuning

Pod와 Service 수가 수만 개에 달하는 클러스터에서는 iptables 규칙도 수만 건이 됩니다. 이 규모에서 kube-proxy가 규칙을 자주 재작성하면 갱신 지연이 누적될 수 있습니다. 아래 두 파라미터로 조정합니다.

- **`minSyncPeriod`** — iptables 규칙 재동기화 최소 간격. 기본값 `1s` 권장.

    `0s`로 설정하면 Endpoint 변경마다 즉시 재작성합니다. 100개 Pod Deployment를 삭제하면 Pod 하나씩 종료될 때마다 100번 재작성이 발생하고, 수만 건의 규칙이 있는 클러스터에서 한 번 재작성에 수 초가 걸리면 kube-proxy가 계속 뒤처진 상태로 반복 재작성합니다. `1s`로 설정하면 1초 안에 발생한 변경을 한 번에 배치 처리해 재작성 횟수가 크게 줄어듭니다.

    `sync_proxy_rules_duration_seconds` 메트릭이 평균 1초를 초과하면 `minSyncPeriod` 값을 높이는 것을 검토하세요.

- **`syncPeriod`** — 외부 컴포넌트가 iptables 규칙을 변경했을 때 감지하는 주기. 기본값 사용 권장. `1h` 같은 매우 큰 값은 기능 손해가 성능 이득보다 크므로 비권장합니다.

```bash
# 현재 설정 확인
kubectl describe cm -n kube-system kube-proxy-config | grep -A5 'iptables:'
# iptables:
#   minSyncPeriod: 1s
#   syncPeriod: 30s
```

---

## CoreDNS

Pod의 `/etc/resolv.conf`는 nameserver로 `kube-dns` Service의 ClusterIP를 가리킵니다. DNS 쿼리 자체도 위에서 설명한 kube-proxy DNAT을 거쳐 CoreDNS Pod에 도달합니다. kube-proxy가 정상 동작하지 않으면 ClusterIP 접근뿐 아니라 DNS 자체가 먼저 끊깁니다.

### Corefile

EKS가 기본으로 배포하는 Corefile 구성입니다.

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

`lameduck 5s`는 CoreDNS Pod이 SIGTERM을 받은 뒤 실제 종료 전 **5초간 DNS 쿼리에 정상 응답을 유지**하는 Graceful Shutdown 메커니즘입니다. Pod이 삭제되면 Kubernetes는 SIGTERM 전송과 동시에 EndpointSlice에서 해당 Pod를 제거하고, kube-proxy는 이를 반영해 iptables를 갱신합니다. 이 갱신이 완료되기 전까지 일부 노드는 여전히 종료 중인 CoreDNS Pod로 DNS 쿼리를 보낼 수 있습니다.

`lameduck 5s`는 이 전환 구간 동안 CoreDNS가 계속 응답할 수 있도록 실제 프로세스 종료를 5초 지연합니다.

위 [iptables Performance Tuning](#iptables-performance-tuning) 섹션에서 다룬 것처럼, 대규모 클러스터에서 kube-proxy의 iptables 갱신은 수 초씩 지연될 수 있습니다. lameduck 시간이 이 갱신 지연보다 짧으면 CoreDNS가 종료된 후에도 일부 노드가 해당 Pod로 DNS 쿼리를 보내는 구간이 생깁니다.

!!! tip
    Pod 수가 많은 클러스터는 `lameduck 30s`로 늘리는 것을 권장합니다.

### Large-Cluster Optimization

노드당 Pod 수가 많아 DNS 쿼리가 집중될 때, cache capacity를 높이고 upstream 동시 요청 수를 제한해 CoreDNS 과부하를 방지합니다.

!!! tip "Cache & Forward Tuning"
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
    ```

### EKS Managed Add-on

위에서 다룬 `lameduck`, PDB, readinessProbe 개선사항은 EKS managed add-on이 이미 기본 적용합니다. 직접 구성할 필요는 없지만, 어떤 항목이 추가되었는지 파악해두면 Corefile을 직접 관리할 때 중복 설정을 피할 수 있습니다.

`topologySpreadConstraints`
:   AZ별 CoreDNS Pod 균등 분배. 기본값은 `ScheduleAnyway`로 소프트 분산이며, 애드온 configuration으로 커스터마이징할 수 있습니다.

    ```bash
    cat <<'EOF' > topologySpreadConstraints.yaml
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            k8s-app: kube-dns
    EOF

    aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name coredns \
      --configuration-values 'file://topologySpreadConstraints.yaml'
    ```

`PDB (Pod Disruption Budget)`
:   노드 드레인 시 CoreDNS Pod이 동시에 종료되지 않도록 보호합니다.

`lameduck 5s`
:   CoreDNS 재시작 및 롤아웃 중 DNS 실패를 최소화하기 위해 health 플러그인에 기본 추가되었습니다.

`readinessProbe`
:   `/health` → `/ready`로 변경되어 CoreDNS가 실제로 요청을 처리할 수 있을 때만 트래픽을 받습니다.
