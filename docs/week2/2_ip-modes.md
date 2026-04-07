# IP Allocation Modes

Amazon VPC CNI는 세 가지 IP 할당 모드를 지원합니다. 클러스터 규모, 인스턴스 유형, VPC 주소 공간 여부에 따라 적합한 모드가 달라집니다.

<div class="grid cards" markdown>

- **Secondary IP**

    기본 모드로 ENI의 Secondary IP를 Pod에 1:1로 할당합니다.

    - :material-check-circle: 기본값, 별도 설정 불필요
    - :material-close-circle: 노드당 배치 가능한 Pod 수 제한
    - :material-cog: 설정 복잡도: 낮음

- **Prefix Delegation**

    ENI 슬롯에 /28 Prefix를 할당하여 IP 할당 효율을 높입니다.

    - :material-check-circle: 노드당 Pod 수 대폭 증가
    - :material-alert-circle: Nitro 인스턴스 필요
    - :material-cog: 설정 복잡도: 중간

- **Custom Networking**

    Pod에 노드와 다른 서브넷 CIDR을 부여하여 VPC IP를 절약합니다.

    - :material-check-circle: VPC IP 절약
    - :material-close-circle: Primary ENI 미사용으로 maxPods 감소
    - :material-cog: 설정 복잡도: 높음

</div>

---

## Modes

=== "Secondary IP"

    ENI의 Secondary IP를 Pod에 1:1로 할당하는 방식으로 별도 설정 없이 사용할 수 있으며, 구조가 단순하고 운영 부담이 낮습니다.

    ```mermaid
    graph LR
        ENI1["Primary ENI\nPrimary IP: 192.168.1.10"] --> P1["Pod 1\n192.168.1.20"]
        ENI1 --> P2["Pod 2\n192.168.1.21"]
        ENI1 --> P3["Pod 3\n192.168.1.22"]
        ENI2["Secondary ENI\nPrimary IP: 192.168.1.30"] --> P4["Pod 4\n192.168.1.40"]
        ENI2 --> P5["Pod 5\n192.168.1.41"]
    ```

    다만 IP를 1:1로 소비하는 구조상, 노드당 배치할 수 있는 Pod 수는 ENI 슬롯 수를 넘을 수 없습니다. [Background에서 살펴본 것처럼](./0_background.md#eni-elastic-network-interface) `maxPods`는 ENI 수와 ENI당 슬롯 수에 의해 결정되며, 공식 및 인스턴스 유형별 한도는 [Pod Capacity](./3_pod-capacity.md)를 참고하세요.

=== "Prefix Delegation"

    <a id="prefix-delegation"></a>
    ENI 슬롯 하나에 개별 IPv4 주소 대신 /28(16개의 IP주소) IPv4 주소 Prefix를 할당하는 방식으로 Amazon VPC CNI를 구성할 수 있습니다.

    아래와 같은 흐름으로 동작하게 됩니다.
    ![Prefix Delegation — Pod IP 할당 플로우](https://docs.aws.amazon.com/images/eks/latest/best-practices/images/networking/pm_image-2.jpeg)
    *[Source: Prefix Mode for Linux](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)*

    이를 통해 ENI 수는 그대로이지만 확보 가능한 IP 수를 크게 늘릴 수 있습니다. 예를 들어 c5.large(ENI당 10 슬롯, ENI 3개)의 경우 Secondary IP 모드에서는 최대 27개의 Pod만 배치할 수 있지만, Prefix Delegation을 사용하면 슬롯 27개 × 슬롯당 16개로 총 432개의 IP를 사용할 수 있습니다.

    ![Prefix Delegation — 두 워커 서브넷 비교](https://docs.aws.amazon.com/images/eks/latest/best-practices/images/networking/pm_image.png)
    *[Source: Prefix Mode for Linux](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)*
    
    #### Nitro-based instances

    이 기능은 Nitro 기반 인스턴스에서만 사용할 수 있습니다. Prefix Delegation은 ENI 슬롯에 연속된 IP 블록을 바인딩하는 방식이며, 이를 하드웨어 수준에서 지원하는 것이 Nitro 하이퍼바이저입니다. 반면, 이전 세대 Xen 기반 인스턴스(m4, c4 등)는 ENI 슬롯당 단일 IP만 바인딩할 수 있는 구조입니다. T3, M5, C5, M6i, C6i 등 현재 주력 인스턴스는 모두 Nitro 기반입니다.

    ```bash
    # Nitro 인스턴스 여부 확인
    aws ec2 describe-instance-types --instance-types t3.medium \
      --query "InstanceTypes[].Hypervisor"
    # ["nitro"]
    ```
    
    #### Allocation
    
    Prefix Delegation 활성화 시 `WARM_PREFIX_TARGET`을 통해 유지할 Prefix 수를 제어합니다.
    단, `WARM_IP_TARGET` 또는 `MINIMUM_IP_TARGET`을 함께 설정할 경우 `WARM_PREFIX_TARGET`은 무시됩니다. 자세한 내용은 [VPC CNI Architecture](./1_vpc-cni.md#warm-pool-environment-variables)를 참고하세요.

    !!! warning "Update maxPods"
        사용 가능한 IP 수가 증가하더라도 kubelet의 `maxPods` 설정은 자동으로 변경되지 않습니다.
        Managed Node Group의 경우 EKS가 `maxPods` 값을 userdata에 주입하므로,
        launch template의 bootstrap 설정에서 `--max-pods` 값을 명시적으로 설정해야 합니다.
        자세한 내용은 [Pod Capacity](./3_pod-capacity.md)를 참고하세요.

    !!! warning "Subnet Fragmentation"
        Prefix Delegation은 서브넷에서 연속된 /28 Prefix를 예약합니다.
        이미 개별 IP가 분산되어 할당된 서브넷(fragmented subnet)에서는
        연속된 16개의 IP 블록을 확보하지 못해 Prefix 할당이 실패할 수 있습니다.
        실패 시 VPC CNI 로그에 다음과 같은 오류가 기록됩니다:

        ```
        failed to allocate a private IP/Prefix address: InsufficientCidrBlocks:
        There are not enough free cidr blocks in the specified subnet to satisfy the request.
        ```

        VPC Subnet CIDR Reservation으로 Prefix 전용 공간을 미리 예약하거나,
        Prefix Delegation 전용 신규 서브넷을 생성하는 것이 권장됩니다.

=== "Custom Networking"

    VPC의 RFC 1918 주소 공간이 고갈되었거나 노드와 Pod CIDR을 분리해야 할 때 사용합니다. Pod에 노드와 다른 서브넷 CIDR을 부여해 Pod 트래픽이 VPC의 기본 주소 공간을 소비하지 않도록 구성합니다.

    ```mermaid
      graph LR
          subgraph VPC["VPC 10.0.0.0/16"]
              Node1["Node 1<br/>10.0.1.10"]
              Node2["Node 2<br/>10.0.1.11"]
          end
      
          subgraph PodCIDR["Pod CIDR 100.64.0.0/16"]
              Pod1["Pod 1<br/>100.64.1.5"]
              Pod2["Pod 2<br/>100.64.1.6"]
              Pod3["Pod 3<br/>100.64.2.5"]
          end
      
          Node1 -->|Secondary<br/>ENI| Pod1
          Node1 -->|Secondary<br/>ENI| Pod2
          Node2 -->|Secondary<br/>ENI| Pod3
    ```

    Pod 전용 대역으로는 `100.64.0.0/10`(RFC 6598, CG-NAT 대역)을 주로 씁니다. RFC 1918 주소(`10.0.0.0/8` 등)는 온프레미스나 피어링된 VPC와 이미 겹치는 경우가 많아 고갈되기 쉽지만, CG-NAT 대역은 공인 인터넷에서 라우팅되지 않고 기업 내부망에서도 거의 쓰이지 않습니다. AWS VPC에서는 보조 CIDR로 연결할 수 있어, RFC 1918이 고갈된 환경에서 현실적인 추가 주소 공간이 됩니다.
    
    | CIDR | 설명 |
    |------|------|
    | `100.64.0.0/10` | CG-NAT 대역 — AWS VPC에서 사용 가능 |
    | `198.19.0.0/16` | IANA 벤치마크 대역 — 내부 전용 |

    ???+ info "Trade-offs"
        - Pod 트래픽이 노드의 Primary ENI가 아닌 Secondary ENI를 통해 나갑니다.
        - Primary ENI 슬롯이 Pod 할당에서 제외되므로 노드당 `maxPods`이 줄어듭니다.
        - 기본 모드에서는 VPC CNI가 Pod 트래픽을 노드의 Primary ENI IP로 SNAT해서 내보냅니다. Custom Networking에서는 Pod이 별도 서브넷의 Secondary ENI에 있어 이 경로가 적용되지 않습니다. `AWS_VPC_K8S_CNI_EXTERNALSNAT=true`로 VPC CNI 자체 SNAT을 비활성화하고, Pod용 서브넷에 NAT Gateway 라우팅을 별도로 구성해야 합니다.
