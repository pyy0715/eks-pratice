# IP Allocation Modes

Amazon VPC CNI는 세 가지 IP 할당 모드를 지원합니다. 클러스터 규모, 인스턴스 유형, VPC 주소 공간 여부에 따라 적합한 모드가 달라집니다.

<div class="grid cards" markdown>

- **Secondary IP**

    기본 모드로 ENI의 Secondary IP를 Pod에 1:1로 할당합니다.

    - :material-check-circle: 기본값, 별도 설정 불필요  
    - :material-close-circle: 노드당 배치 가능한 Pod 수 제한  
    - :material-cog: 설정 복잡도: **낮음**

- **Prefix Delegation**

    ENI 슬롯에 /28 Prefix를 할당하여 IP 할당 효율을 높입니다.

    - :material-check-circle: IP 할당 효율 향상  
    - :material-alert-circle: Nitro 인스턴스 필요  
    - :material-cog: 설정 복잡도: **중간**

- **Custom Networking**

    Pod에 노드와 다른 서브넷 CIDR을 부여하여 VPC IP를 절약합니다.

    - :material-check-circle: VPC IP 절약  
    - :material-close-circle: 구성에 따라 Pod 수 제한 발생  
    - :material-cog: 설정 복잡도: **높음**

</div>
---

## Modes

=== "Secondary IP"

    ENI의 Secondary IP를 Pod에 1:1로 할당하는 방식으로  별도 설정 없이 사용할 수 있으며, 구조가 단순하고 운영 부담이 낮습니다.

    ```mermaid
    graph LR
        ENI1["Primary ENI\nPrimary IP: 192.168.1.10"] --> P1["Pod 1\n192.168.1.20"]
        ENI1 --> P2["Pod 2\n192.168.1.21"]
        ENI1 --> P3["Pod 3\n192.168.1.22"]
        ENI2["Secondary ENI\nPrimary IP: 192.168.1.30"] --> P4["Pod 4\n192.168.1.40"]
        ENI2 --> P5["Pod 5\n192.168.1.41"]
    ```

    - ENI의 Secondary IPv4 주소를 Pod에 1:1로 할당
    - Pod 수 상한은 ENI 및 IP 할당 한도에 의해 결정됨
    - 설정이 단순하고 기본 동작으로 사용 가능


    Pod 수 상한은 ENI 수와 ENI당 Secondary IP 슬롯 수에 의해 결정됩니다. 공식 및 인스턴스 유형별 한도, Managed Node Group에서의 우선순위는 [Pod Capacity](./3_pod-capacity.md)를 참고하세요.

=== "Prefix Delegation"

    **언제**: Pod 밀도 부족, Nitro 기반 인스턴스

    ENI 슬롯 하나에 개별 IP 대신 **/28 프리픽스(16개 IP)**를 할당합니다. ENI 수는 동일하지만 확보 가능한 IP 수가 대폭 증가합니다.

    ### 동작 방식

    ![Prefix Delegation — 두 워커 서브넷 비교](https://docs.aws.amazon.com/images/eks/latest/best-practices/images/networking/pm_image.png)
    *[Source: Prefix Mode for Linux](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)*

    ![Prefix Delegation — Pod IP 할당 플로우](https://docs.aws.amazon.com/images/eks/latest/best-practices/images/networking/pm_image-2.jpeg)
    *[Source: Prefix Mode for Linux](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)*

    ENI 슬롯 하나에 개별 IP 대신 **/28 prefix(16개 IP)**를 할당합니다. ENI 수는 그대로이지만 확보 가능한 IP 수가 크게 늘어납니다. 예를 들어 c5.large(ENI당 10 슬롯, ENI 3개)는 Secondary IP 모드에서 최대 27개 Pod이지만, Prefix Delegation에서는 슬롯당 16개 × 27슬롯 = **432개**의 IP를 확보할 수 있습니다.

    Nitro 기반 인스턴스에서만 사용 가능합니다. Prefix Delegation은 ENI 슬롯에 연속된 IP 블록을 바인딩하는 기능으로, 이를 하드웨어 수준에서 지원하는 것이 Nitro 하이퍼바이저입니다. 이전 세대 Xen 기반 인스턴스(m4, c4 등)는 ENI 슬롯당 단일 IP만 바인딩할 수 있는 구조입니다. T3, M5, C5, M6i, C6i 등 현재 주력 인스턴스는 모두 Nitro 기반입니다.

    `/28`이 할당 단위인 이유는 IPv4에서 prefix 할당이 가능한 가장 작은 블록이기 때문입니다. 더 크게 가면(/27 = 32개) 서브넷 주소 소진이 빨라지고, 더 작게 가면(/29 = 8개) Pod 밀도 향상 효과가 줄어듭니다.

    서브넷에 **연속된 /28 블록**이 있어야 한다는 점도 주의가 필요합니다. 기존 ENI에 새 prefix를 추가하는 작업은 1초 이내에 완료되지만, 서브넷이 단편화되어 연속된 16개 IP를 찾지 못하면 prefix 할당이 실패합니다.

    ### 전제 조건 확인

    ```bash
    # Nitro 인스턴스 여부 확인
    aws ec2 describe-instance-types --instance-types t3.medium \
      --query "InstanceTypes[].Hypervisor"
    # ["nitro"]
    ```

    ### 활성화 방법

    ```hcl
    # eks.tf — vpc-cni 애드온 설정
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
    ```

    또는 eksctl로 기존 클러스터에 적용:

    ```bash
    kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
    ```

    ### Warm Pool 환경 변수와의 관계

    Prefix Delegation 활성화 시 `WARM_PREFIX_TARGET`으로 여유 /28 프리픽스 수를 제어합니다. 단, `WARM_IP_TARGET` 또는 `MINIMUM_IP_TARGET`을 함께 설정하면 `WARM_PREFIX_TARGET`은 무시됩니다. 자세한 내용은 [VPC CNI Architecture](./1_vpc-cni.md#warm-pool-environment-variables)를 참고하세요.

    !!! warning "maxPods는 별도로 조정 필요"
        Prefix Delegation을 활성화해도 **maxPods 상한은 자동으로 늘어나지 않습니다.**
        Managed Node Group은 EKS가 maxPods를 userdata에 주입하므로,
        커스텀 AMI + `--max-pods` 조합으로 직접 변경해야 합니다.
        자세한 내용은 [Pod Capacity](./3_pod-capacity.md)를 참고하세요.

    !!! warning "서브넷 단편화 주의"
        Prefix Delegation은 서브넷에서 **연속된 /28 블록**을 예약합니다.
        이미 많은 개별 IP가 흩어져 할당된 서브넷(fragmented subnet)에서는
        연속된 16개 IP를 찾지 못해 prefix 할당이 실패합니다.
        실패 시 VPC CNI 로그에 다음 오류가 기록됩니다:

        ```
        failed to allocate a private IP/Prefix address: InsufficientCidrBlocks:
        There are not enough free cidr blocks in the specified subnet to satisfy the request.
        ```

        **해결책**: VPC Subnet CIDR Reservation으로 prefix 전용 공간을 미리 예약하거나,
        Prefix Delegation 전용 신규 서브넷을 생성하는 것이 권장됩니다.
        가능한 한 Prefix Delegation 전용 서브넷을 별도로 운영하는 것을 권장합니다.

=== "Custom Networking"

    **언제**: VPC의 RFC 1918 주소 고갈, 노드와 Pod CIDR 분리 필요

    Pod에 **노드와 다른 서브넷 CIDR**을 부여합니다. VPC의 RFC 1918 주소 공간이 부족할 때 Pod가 별도 대역을 사용하도록 구성합니다.

    ### 동작 방식

    ```mermaid
    graph TD
        subgraph VPC["VPC (10.0.0.0/16 — RFC 1918)"]
            Node1["노드 1\n10.0.1.10 (Primary ENI)"]
            Node2["노드 2\n10.0.1.11 (Primary ENI)"]
        end
        subgraph PodCIDR["별도 Pod CIDR (100.64.0.0/16)"]
            Pod1["Pod 1\n100.64.1.5"]
            Pod2["Pod 2\n100.64.1.6"]
            Pod3["Pod 3\n100.64.2.5"]
        end
        Node1 -->|Secondary ENI| Pod1
        Node1 -->|Secondary ENI| Pod2
        Node2 -->|Secondary ENI| Pod3
    ```

    - Pod에 노드와 다른 서브넷 CIDR 부여
    - Pod가 VPC의 RFC 1918 주소를 소비하지 않게 됨

    Pod 전용 대역으로는 `100.64.0.0/10`(RFC 6598, CG-NAT 대역)을 주로 씁니다. RFC 1918 주소(`10.0.0.0/8` 등)는 온프레미스나 피어링된 VPC와 이미 겹치는 경우가 많아 고갈되기 쉽지만, CG-NAT 대역은 공인 인터넷에서 라우팅되지 않고 기업 내부망에서도 거의 쓰이지 않습니다. AWS VPC에서는 보조 CIDR로 연결할 수 있어, RFC 1918이 고갈된 환경에서 현실적인 추가 주소 공간이 됩니다.

    !!! warning "CG-NAT 대역 기존 사용 여부 먼저 확인"
        온프레미스 환경이나 Transit Gateway에 연결된 다른 VPC에서 이미 `100.64.0.0/10` 대역을
        사용 중이라면 충돌이 발생합니다. Custom Networking을 적용하기 전에
        기존 네트워크 환경에서 해당 대역 사용 여부를 반드시 확인하세요.

    ### 추천 대역

    | CIDR | 설명 |
    |------|------|
    | `100.64.0.0/10` | CG-NAT 대역 — AWS VPC에서 사용 가능 |
    | `198.19.0.0/16` | IANA 벤치마크 대역 — 내부 전용 |

    !!! warning "트레이드오프"
        - Pod 트래픽이 노드의 **Primary ENI가 아닌 Secondary ENI**를 통해 나갑니다.
        - Primary ENI가 Pod에 사용되지 않으므로 **노드당 Pod 수 상한이 줄어듭니다**.
          (Primary ENI 슬롯이 Pod 할당에서 제외됨)
        - Pod에서 인터넷으로 나가는 SNAT 경로가 달라지므로 추가 설정이 필요합니다.
        - `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` 및 `ENIConfig` CRD 설정이 필요합니다.

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
