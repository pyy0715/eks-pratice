# Overview

오토스케일링은 워크로드 변동에 따라 컴퓨팅 리소스를 탄력적으로 관리하는 메커니즘입니다. 수동 운영 시 발생하는 자원 낭비와 가용성 저하 문제를 자동화로 해결하는 데 목적이 있습니다.

Kubernetes는 이를 Pod과 Node 두 계층으로 나누어 처리합니다. 부하 발생 시 Pod 확장이 우선적으로 수행되며, 기존 Node에 더 이상 Pod을 배치할 수 없는 시점에 Node 확장이 뒤따르는 유기적인 구조를 가집니다.

| Layer | Tool |
|---|---|
| Pod | HPA, VPA, KEDA |
| Node | Cluster Autoscaler, Karpenter, EKS Auto Mode |

---

## Pod Scaling

Pod 스케일링은 수평, 수직 두 방향으로 이루어집니다. **Horizontal Scaling**은 replica 수를 늘려 처리 용량을 확보하며 Stateless 워크로드에 적합합니다. **Vertical Scaling**은 replica 수는 그대로 두고 각 Pod의 CPU/Memory resource request를 늘리며, 노드 인스턴스 타입의 최대 사양이 상한입니다.

=== "HPA"

    HPA(Horizontal Pod Autoscaler)는 메트릭을 기반으로 Deployment의 replica 수를 자동 조정합니다. `kube-controller-manager` 내부에서 15초 간격으로 동작하며, 현재 메트릭 값과 목표값의 비율로 필요한 replica 수를 계산합니다. CPU/Memory 외에 Custom, External 메트릭도 지원합니다.

=== "VPA"

    VPA(Vertical Pod Autoscaler)는 Pod의 실제 리소스 사용량을 분석해 `resources.requests`를 자동 조정합니다. Kubernetes 내장 기능이 아니라 별도 add-on으로 설치해야 합니다. 추천값을 적용할 때는 기존 Pod를 evict하고 새 Pod로 교체합니다.

=== "KEDA"

    KEDA(Kubernetes Event-Driven Autoscaling)는 SQS 큐 길이, Kafka consumer lag 같은 외부 이벤트를 트리거로 Pod를 스케일링합니다. 내부적으로 HPA를 생성하고 관리하므로 기존 Kubernetes 스케줄러와의 통합은 그대로 유지됩니다.

    ![KEDA Overview — ScaledObject, HPA, External Event Sources](https://d1.awsstatic.com/onedam/marketing-channels/website/aws/en_US/perscriptive-guidance/approved/images/8f298b6eea5d449135d710d590f87209-event-driven-application-autoscaling-keda-amazon-eks-architecture-overview-2094x1522.d6e51a424854a89008e3cd6c45744906ad7a9414.png)

    *[Source: AWS Solutions](https://aws.amazon.com/ko/solutions/guidance/event-driven-application-autoscaling-with-keda-on-amazon-eks/)*

---

## Node Scaling

노드 스케일링은 Pending 또는 Unschedulable 상태의 Pod가 발생했을 때 새 노드를 프로비저닝하고, 유휴 노드를 종료합니다. EKS에서는 [데이터 플레인 컴퓨팅 옵션](../week1/2_data-plane.md)에 따라 선택 가능한 방식이 제한됩니다.

=== "Cluster Autoscaler"

    Pending Pod가 발생하면 ASG(Auto Scaling Group)의 DesiredCapacity를 조정해 EC2 인스턴스를 추가하고, 유휴 노드를 제거합니다. ASG 기반 EKS 노드 그룹에서 동작하며 AWS Auto Scaling 정책과 함께 사용됩니다.

=== "Karpenter"

    Unschedulable Pod의 resource request를 분석해 EC2 Fleet API로 적합한 인스턴스 타입을 선택하고 1분 이내에 직접 프로비저닝합니다. ASG를 거치지 않고 EC2를 직접 제어하므로 CAS보다 빠릅니다.

=== "EKS Auto Mode"

    노드 프로비저닝과 관리를 EKS에 완전히 위임합니다.

---

## EKS Auto Scaling Summary

EKS에서 사용하는 주요 오토스케일링 도구를 트리거, 동작, 대상 기준으로 비교합니다.

| | Trigger | Action | Target |
|---|---|---|---|
| **HPA** | Pod 메트릭 초과 | 신규 Pod Provisioning | Pod Scale Out |
| **VPA** | Pod 자원 부족 | Pod 교체(자동/수동) | Pod Scale Up |
| **CAS** | Pending Pod 존재 | 신규 노드 Provisioning | Node Scale Out |
| **Karpenter** | Unschedulable Pod 감지 | EC2 Fleet으로 노드 생성 | Node Scale Up/Out |
