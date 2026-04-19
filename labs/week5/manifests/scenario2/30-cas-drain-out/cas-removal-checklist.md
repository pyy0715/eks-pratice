# CAS Removal Checklist

Karpenter로 전환이 완료되면 CAS를 제거합니다. 아래 순서를 지키지 않으면 워크로드가 Pending으로 방치되거나 ASG가 0까지 축소되는 동안 Karpenter가 capacity를 따라잡지 못하는 구간이 생깁니다.

## Pre-flight Check

```bash
kubectl get nodeclaims
kubectl get nodes -L provisioner,karpenter.sh/nodepool
```

- [ ] Karpenter 노드가 전체 워크로드 capacity를 감당하고 있음을 확인
- [ ] `kubectl get pods -o wide`로 CAS ASG 노드 전용 Pod이 남아 있지 않음을 확인

## Removal Steps

### 1. Scale CAS Deployment to 0

```bash
kubectl -n kube-system scale deploy cluster-autoscaler-aws-cluster-autoscaler --replicas=0
```

이 시점부터 CAS는 스케일 결정을 멈춥니다. 기존 노드는 그대로 유지됩니다.

### 2. Reduce ng-cas ASG to min/desired = 0

Terraform `eks.tf`의 `ng_cas` 블록을 다음과 같이 수정합니다.

```hcl
desired_size = 0
min_size     = 0
```

`terraform apply`를 실행하면 EKS가 ASG desired를 0으로 낮추고 노드를 종료합니다. 종료 속도는 `cas-scaleout` Deployment의 PDB가 제한합니다.

### 3. Karpenter Takes Over Capacity

ng-cas 노드가 종료되면서 Pending이 된 Pod은 Karpenter가 NodeClaim으로 프로비저닝합니다.

```bash
kubectl get nodeclaims -w
kubectl get pods -A -o wide | grep Pending
```

### 4. Uninstall CAS Helm Release

```bash
helm -n kube-system uninstall cluster-autoscaler
```

### 5. Clean Up IAM

`iam.tf`에서 `aws_iam_role.cas_pod_identity`와 `aws_iam_policy.cas_autoscaling_policy`를 제거한 뒤 `terraform apply`를 실행합니다.

## Final Checks

!!! warning "Order dependency"

    `ng_cas`의 `min_size=0` 설정을 Step 1(CAS scale 0)보다 먼저 적용하면 CAS가 종료 방어 로직을 작동시키면서 불필요한 scaling 이벤트가 발생합니다. Step 1을 반드시 먼저 실행합니다.

- [ ] Karpenter `limits.cpu`가 이관 후 전체 클러스터 capacity 수요를 감당할 수 있는 값인지 재확인
- [ ] CAS 관련 CloudWatch 알림 규칙과 대시보드 쿼리를 정리
