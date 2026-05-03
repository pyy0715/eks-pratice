# Version Lifecycle

Kubernetes 클러스터를 운영한다면 버전 업그레이드는 선택이 아니라 반복적으로 수행해야 하는 운영 작업입니다. 업그레이드를 미루면 보안 패치를 놓치고, 지원 종료된 API로 인해 워크로드가 중단될 수 있습니다. 이 문서에서는 Kubernetes와 Amazon EKS의 릴리스 주기, 지원 정책, 그리고 업그레이드 시 책임 범위를 정리합니다.

---

## Kubernetes Release Cycle

Kubernetes는 [Semantic Versioning](https://semver.org/)을 따르며, 버전은 `x.y.z` (major.minor.patch) 형식으로 표기됩니다.

`x` (major)
:   하위 호환성이 깨지는 변경. 현재까지 `1`에서 변경된 적이 없습니다.

`y` (minor)
:   새 기능 추가, API 변경. 약 4개월마다 릴리스됩니다.

`z` (patch)
:   버그 수정, 보안 패치. minor 릴리스 이후 수시로 제공됩니다.

Kubernetes 프로젝트는 최근 3개 minor 버전을 유지하며, v1.19 이상 각 minor 버전에 12개월의 upstream 지원을 제공합니다[^1].

---

## Amazon EKS Support Timeline

Amazon EKS는 upstream Kubernetes 릴리스를 따르되, AWS 서비스 호환성 테스트를 거쳐 수 주 후에 릴리스합니다. EKS는 동시에 3개 minor 버전을 standard support로 유지합니다.

| Support | Duration | Cost (per cluster/hour) | Behavior at End |
|---------|----------|------|-----------------|
| Standard | 14개월 | $0.10/cluster/hour | Extended 진입 또는 자동 업그레이드 (Version Policy에 따라) |
| Extended | 12개월 | $0.60/cluster/hour | 자동 업그레이드 실행 |

Extended support는 v1.21 이상에 적용되며, 기본적으로 활성화되어 있습니다. VPC CNI, kube-proxy, CoreDNS add-on과 EKS optimized AMI(Amazon Linux, Bottlerocket, Windows)에 대해 보안 패치가 계속 제공됩니다[^2].

### EKS Release Calendar

EKS에서 지원하는 각 Kubernetes 버전의 릴리스 및 지원 종료 일정입니다 (2026-04 기준)[^2].

| Kubernetes Version | Upstream Release | Amazon EKS Release | End of Standard Support | End of Extended Support |
|:------------------:|:----------------:|:-------------------:|:-----------------------:|:-----------------------:|
| 1.35 | 2025-12-17 | 2026-01-27 | 2027-03-27 | 2028-03-27 |
| 1.34 | 2025-08-27 | 2025-10-02 | 2026-12-02 | 2027-12-02 |
| 1.33 | 2025-04-23 | 2025-05-29 | 2026-07-29 | 2027-07-29 |
| 1.32 | 2024-12-11 | 2025-01-23 | 2026-03-23 | 2027-03-23 |
| 1.31 | 2024-08-13 | 2024-09-26 | 2025-11-26 | 2026-11-26 |
| 1.30 | 2024-04-17 | 2024-05-23 | 2025-07-23 | 2026-07-23 |

### Platform Version

각 minor 버전 안에서 EKS는 별도의 platform version(eks.1, eks.2 등)을 릴리스합니다. platform version에는 control plane 설정 변경과 보안 수정이 포함됩니다. EKS가 자동으로 업그레이드하므로 사용자 조치는 필요하지 않습니다[^2].

---

## Kubernetes Version Policy

2024년 7월, Amazon EKS는 클러스터별로 standard support 종료 시점의 동작을 선택할 수 있는 Version Policy를 도입했습니다. `supportType` 속성으로 설정합니다.

`STANDARD`
:   Standard support 종료 시 다음 standard support 버전으로 자동 업그레이드됩니다. Extended support 과금이 발생하지 않습니다.

`EXTENDED`
:   Standard support 종료 후 extended support에 진입합니다. 추가 과금($0.60/cluster/hour)이 발생하며, extended support 종료 시점에 자동 업그레이드됩니다.

Console 또는 CLI에서 설정할 수 있으며, standard support 기간 중에만 변경이 가능합니다[^3].

```bash
aws eks update-cluster-config \
  --name <cluster-name> \
  --upgrade-policy supportType=EXTENDED
```

---

## Shared Responsibility Model

EKS 클러스터 업그레이드에서 AWS와 사용자의 책임 범위는 명확히 구분됩니다.

![EKS Shared Responsibility Model](https://repost.aws/media/postImages/original/IMZdqu0LbcSMKuqlGwkGgunQ) *[Source: Securing Kubernetes workloads in Amazon EKS — AWS re:Post](https://repost.aws/articles/ARBLCFrOUHS_injc6AjeYY3g/aws-re-invent-2024-securing-kubernetes-workloads-in-amazon-eks)*

=== "Control Plane (AWS)"

    사용자가 업그레이드를 시작하면 AWS가 내부적으로 blue/green 방식으로 수행합니다. 업그레이드 중 API server endpoint는 유지되며, 실패 시 자동 롤백됩니다. 한 번에 1 minor 버전만 올릴 수 있습니다.

=== "Data Plane (Customer)"

    노드 업그레이드는 사용자 책임이며, 노드 유형에 따라 방법이 다릅니다. 업그레이드 중 워크로드 가용성을 보장하려면 PodDisruptionBudget와 TopologySpreadConstraints 구성이 필수적입니다.

    | Node Type | Upgrade Method |
    |-----------|---------------|
    | Managed Node Group | Rolling update (자동 cordon/drain) 또는 Blue/Green 교체 |
    | Karpenter | Drift 감지 → 자동 교체 또는 `expireAfter` TTL |
    | Self-managed | AMI 교체 후 ASG rolling update |
    | Fargate | `kubectl rollout restart`로 Pod 재시작 |

=== "Add-ons (Customer)"

    EKS managed add-on은 클러스터 업그레이드 시 자동으로 업그레이드되지 않습니다. 각 add-on의 호환 버전을 확인하고 별도로 업그레이드해야 합니다. add-on 관리에 대한 기본 개념은 [Week 1 — Add-ons and Capabilities](../week1/3_addons.md)를 참고하세요.


[^1]: [Kubernetes Releases](https://kubernetes.io/releases/)
[^2]: [Understand the Kubernetes version lifecycle on EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
[^3]: [View current cluster upgrade policy](https://docs.aws.amazon.com/eks/latest/userguide/view-upgrade-policy.html)
