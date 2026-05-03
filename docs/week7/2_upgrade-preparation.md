# Upgrade Preparation

업그레이드를 시작하기 전에 클러스터 상태를 점검하고, 호환성 이슈를 사전에 식별해야 합니다. 이 문서에서는 인프라 사전 요구사항 검증, EKS Upgrade Insights 활용, deprecated API 탐지 도구, 그리고 add-on 호환성 확인 절차를 정리합니다.

---

## Infrastructure Prerequisites

Control Plane 업그레이드를 시작하려면 다음 세 가지 리소스가 계정에 정상적으로 존재해야 합니다.

**Subnet IP** — EKS는 control plane 업그레이드 시 최소 5개의 가용 IP를 클러스터 생성 시 지정한 서브넷에서 필요로 합니다[^1]. IP가 부족하면 `UpdateClusterConfiguration` API로 동일 VPC, 동일 AZ의 새 서브넷을 추가하거나, VPC에 추가 CIDR 블록을 연결하여 IP 풀을 확장합니다.

```bash
aws ec2 describe-subnets \
    --subnet-ids $(aws eks describe-cluster \
        --name ${CLUSTER_NAME} \
        --query 'cluster.resourcesVpcConfig.subnetIds' \
        --output text) \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,AvailableIpAddressCount]' \
    --output table
```

**IAM Role** — 클러스터 IAM role이 계정에 존재하고, `eks.amazonaws.com` 서비스가 AssumeRole할 수 있어야 합니다.

```bash
ROLE_ARN=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.roleArn'  --output text)

aws iam get-role --role-name ${ROLE_ARN##*/} --query 'Role.AssumeRolePolicyDocument'
```

!!! note "Secrets Encryption"

    Secrets encryption을 활성화한 클러스터는 IAM role에 AWS KMS 키 사용 권한도 필요합니다.

**Security Group** — EKS는 클러스터 생성 시 `eks-cluster-sg-{name}-{uniqueID}` 형태의 security group을 자동 생성합니다. 기본 규칙은 control plane과 node 간 모든 트래픽을 양방향으로 허용합니다.

!!! warning "Outbound Restriction"

    아웃바운드 규칙을 제한하는 경우, 노드 간 통신 포트, ECR/인터넷 접근, IPv4/IPv6 별도 룰을 명시적으로 허용해야 합니다. 변경 전 비프로덕션 환경에서 모든 Pod의 정상 동작을 검증하세요.

---

## EKS Upgrade Insights

EKS Upgrade Insights는 클러스터의 업그레이드 준비 상태를 자동으로 검사하는 managed 기능입니다. EKS가 클러스터 audit log를 매일 스캔하여 deprecated resource를 탐지하며, Console의 Upgrade Insights 탭 또는 API/CLI로 결과를 조회할 수 있습니다[^2].

2025년 3월, upgrade insights에서 ERROR가 발견된 클러스터의 업그레이드를 차단하는 기능이 도입되었으나 현재 일시적으로 롤백된 상태입니다[^3]. 향후 재도입될 수 있으므로 insights 상태를 항상 PASSING으로 유지하는 것이 권장됩니다.

검사 항목은 EKS가 관리하는 curated list로, Kubernetes 버전 변경에 따라 수시로 업데이트됩니다. API 응답에서 반환되는 주요 정보는 두 가지입니다.

- **deprecationDetails** — 대상 버전에서 deprecated/removed된 API를 사용하는 리소스 목록과 호출 client 정보
- **addonCompatibilityDetails** — 설치된 EKS managed add-on이 대상 버전과 호환되는지 여부

각 insight에는 다음 세 가지 상태값이 부여됩니다.

| Status | Meaning |
|--------|---------|
| ERROR | N+1 버전에서 제거된 API를 사용 중이거나 호환되지 않는 구성이 발견됨. 업그레이드가 차단될 수 있음 |
| WARNING | N+2 이상 버전에서 deprecation이 예정됨. 즉시 조치가 필요하지는 않음 |
| PASSING | 해당 검사에서 문제가 발견되지 않음 |
| UNKNOWN | 백엔드 처리 오류로 검사를 완료하지 못함 |

![Upgrade Insights console](https://d2908q01vomqb2.cloudfront.net/fe2ef495a1152561572949784c16bf23abb28057/2023/12/12/Upgrade-insights.jpg)

*Source: [Accelerate the testing and verification of Amazon EKS upgrades with upgrade insights — AWS Containers Blog](https://aws.amazon.com/blogs/containers/accelerate-the-testing-and-verification-of-amazon-eks-upgrades-with-upgrade-insights/)*

CLI로도 조회할 수 있습니다.

```bash
aws eks list-insights \
    --filter kubernetesVersions=1.31 \
    --cluster-name $CLUSTER_NAME | jq .
```

특정 insight의 상세 정보는 `describe-insight`으로 확인합니다. insight를 클릭하면 deprecated API를 호출한 userAgent와 빈도도 확인할 수 있습니다.

```bash
aws eks describe-insight \
    --cluster-name $CLUSTER_NAME \
    --id <insight-id>
```

![Deprecation details](https://d2908q01vomqb2.cloudfront.net/fe2ef495a1152561572949784c16bf23abb28057/2023/12/12/Deprecation-details.jpg)

*Source: [Accelerate the testing and verification of Amazon EKS upgrades with upgrade insights — AWS Containers Blog](https://aws.amazon.com/blogs/containers/accelerate-the-testing-and-verification-of-amazon-eks-upgrades-with-upgrade-insights/)*

---

## Deprecated API Detection and Migration

Upgrade Insights 외에도 deprecated API를 탐지하고 변환하는 도구를 활용할 수 있습니다.

=== "Detection"

    [pluto](https://github.com/FairwindsOps/pluto)는 매니페스트 파일, Helm chart, 디렉터리를 정적 스캔하여 deprecated/removed API 사용을 탐지합니다. GitOps repo 전체를 대상으로 스캔할 수 있어 CI/CD 파이프라인에 통합하기 적합합니다.

    ```bash
    pluto detect-files -d ~/environment/eks-gitops-repo/
    ```

    [kubent](https://github.com/doitintl/kube-no-trouble)는 live 클러스터에 연결하여 실행 중인 리소스의 deprecated API를 탐지합니다. Cluster, Helm v3 등 여러 collector에서 리소스를 수집하고, 버전별 deprecation ruleset과 대조합니다.

    ```bash
    kubent
    ```

=== "Migration"

    [kubectl-convert](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-convert-plugin)는 deprecated API를 사용하는 매니페스트를 새 API 버전으로 자동 변환합니다. 별도 플러그인으로 설치해야 합니다.

    ```bash
    kubectl convert -f deployment.yaml --output-version apps/v1
    ```

    변환 후에는 `kubectl apply`로 재적용해야 하며, 원본 매니페스트를 백업해 두는 것을 권장합니다.

---

## Add-on Compatibility

EKS managed add-on은 클러스터 업그레이드 시 자동으로 업그레이드되지 않습니다. 각 add-on의 호환 버전을 사전에 확인하고 업그레이드 계획에 포함해야 합니다.

`describe-addon-versions` API로 대상 Kubernetes 버전과 호환되는 add-on 버전을 조회합니다.

=== "CoreDNS"

    ```bash
    aws eks describe-addon-versions \
      --addon-name coredns \
      --kubernetes-version 1.31 \
      --output table \
      --query "addons[].addonVersions[:5].{Version:addonVersion,Default:compatibilities[0].defaultVersion}"
    ```

=== "kube-proxy"

    ```bash
    aws eks describe-addon-versions \
      --addon-name kube-proxy \
      --kubernetes-version 1.31 \
      --output table \
      --query "addons[].addonVersions[:5].{Version:addonVersion,Default:compatibilities[0].defaultVersion}"
    ```

=== "VPC CNI"

    ```bash
    aws eks describe-addon-versions \
      --addon-name vpc-cni \
      --kubernetes-version 1.31 \
      --output table \
      --query "addons[].addonVersions[:5].{Version:addonVersion,Default:compatibilities[0].defaultVersion}"
    ```

Helm으로 설치한 add-on은 각 프로젝트 문서에서 호환성을 직접 확인해야 합니다.

| Add-on | Compatibility Note |
|--------|--------------------|
| AWS Load Balancer Controller | EKS 버전별 호환 매트릭스 확인 필요 |
| EBS/EFS CSI Driver | EKS managed add-on으로 전환 권장 |
| Metrics Server | GitHub releases에서 K8s 호환 버전 확인 |
| Cluster Autoscaler | K8s scheduler와 밀접하므로 클러스터와 동시에 업그레이드 |
| Karpenter | [Karpenter 업그레이드 가이드](../week3/4_karpenter.md) 참조 |

!!! warning "VPC CNI Version Bump"

    Amazon VPC CNI의 EKS add-on 배포는 한 번에 1 minor 버전만 올릴 수 있습니다. 여러 버전을 건너뛸 수 없으므로 순차적으로 업그레이드해야 합니다.

---

## Pre-upgrade Checklist

업그레이드를 시작하기 전에 확인해야 할 항목을 정리합니다.

- [ ] 서브넷에 가용 IP 5개 이상 확인
- [ ] 클러스터 IAM role 존재 및 AssumeRole policy 확인
- [ ] Security group 존재 확인 (커스텀 규칙이 있으면 업그레이드 호환성 검증)
- [ ] EKS Upgrade Insights 전체 PASSING 확인
- [ ] deprecated/removed API 사용 리소스 식별 및 리팩터링
- [ ] EKS managed add-on 호환 버전 확인
- [ ] Third-party add-on, Helm chart 호환 버전 확인
- [ ] PodDisruptionBudget 구성 확인
- [ ] 클러스터 백업 (선택)

[^1]: [Update existing cluster to new Kubernetes version](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
[^2]: [Cluster Insights for upgrade readiness](https://docs.aws.amazon.com/eks/latest/userguide/cluster-insights.html)
[^3]: [Amazon EKS enforces upgrade insights checks](https://aws.amazon.com/about-aws/whats-new/2025/03/amazon-eks-enforces-upgrade-insights-check-cluster-upgrades/)
