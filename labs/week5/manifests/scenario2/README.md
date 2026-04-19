# Scenario 2 — Cluster Autoscaler → Karpenter Migration

Cluster Autoscaler(CAS)로 노드 스케일을 운영하던 클러스터에 Karpenter를 도입하고, 노드 provisioning과 consolidation 과정에서 발생하는 2가지 incident를 재현합니다.

## Pre-flight Check

```bash
source ../../00_env.sh
kubectl -n kube-system get deploy cluster-autoscaler-aws-cluster-autoscaler karpenter
kubectl get nodes -L eks.amazonaws.com/nodegroup
```

## Step 1 — CAS Scale Baseline

```bash
kubectl apply -f 00-baseline-cas/pdb.yaml
kubectl apply -f 00-baseline-cas/workload-pending.yaml

# CAS가 ng-cas ASG의 desired를 올리는지 관찰
kubectl -n kube-system logs deploy/cluster-autoscaler-aws-cluster-autoscaler --tail=50 -f
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'ng-cas')].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]"
```

**Expected observation** — Pending Pod이 감지되면 CAS가 ASG desired를 올리고, 새 노드가 Ready 상태가 된 뒤 Pod이 배치됩니다.

## Step 2 — Karpenter NodePool

```bash
envsubst < 10-karpenter-install/ec2nodeclass-default.yaml | kubectl apply -f -
kubectl apply -f 10-karpenter-install/nodepool-default.yaml

kubectl get nodepool,ec2nodeclass
kubectl -n kube-system logs deploy/karpenter --tail=50
```

**Expected observation** — Karpenter가 NodePool을 Ready로 만들고, 이후 발생한 Pending Pod에 대해 NodeClaim을 생성합니다.

## Step 3 — Incident #1: Overly Strict PDB Blocking Consolidation

Karpenter는 정상적으로 consolidation을 시도하지만, PDB `minAvailable: 100%`가 모든 disruption을 차단합니다. 노드 교체, 유지보수, consolidation이 모두 불가능해지는 현상을 재현합니다.

```bash
kubectl apply -f incidents/01-consolidation-pdb-violation.yaml

# Karpenter 로그 — consolidation 시도가 PDB에 의해 반복 차단됨
kubectl -n kube-system logs deploy/karpenter --tail=200 | grep -i disrupt

# PDB 상태 — disruptionsAllowed가 0이면 eviction 불가
kubectl get pdb critical-app-pdb -n default -o wide
kubectl get pdb critical-app-pdb -n default -o jsonpath='{.status.disruptionsAllowed}'

# 이벤트에서 drain 실패 흔적
kubectl get events -A --field-selector reason=FailedDraining
```

**Expected observation** — Karpenter 로그에 "cannot disrupt due to PDB"가 반복 나타납니다. PDB `disruptionsAllowed: 0`이므로 단일 pod도 eviction할 수 없습니다. NodePool의 `budgets`는 정상 설정(10%)이지만 PDB가 더 상위에서 모든 disruption을 차단합니다.

**Recovery**

```bash
# PDB를 허용 가능한 수준으로 변경
kubectl patch pdb critical-app-pdb -n default -p '{"spec":{"minAvailable":"80%"}}'
# 또는 maxUnavailable: 1 로 대체
# kubectl patch pdb critical-app-pdb -n default --type=json -p '[{"op":"replace","path":"/spec/minAvailable","value":null},{"op":"add","path":"/spec/maxUnavailable","value":1}]'
```

## Step 4 — Incident #2: NodeClaim Launch Failure

EC2NodeClass에 틀린 IAM role 이름이 설정된 상태에서 Karpenter가 NodeClaim을 생성하려고 시도합니다. EC2 `RunInstances` API가 실패하거나, 인스턴스가 생성되어도 kubelet이 EKS API에 인증하지 못해 노드가 cluster에 join하지 못합니다.

```bash
# broken EC2NodeClass + NodePool + trigger 워크로드 배포
envsubst < incidents/02-nodeclaim-launch-failure.yaml | kubectl apply -f -

# NodeClaim 상태 확인
kubectl get nodeclaim -o wide
# NAME              STATUS         AGE
# broken-xxxxx      LaunchFailed   30s

# NodeClaim 상세 — status.conditions에서 에러 메시지 확인
kubectl describe nodeclaim -l karpenter.sh/nodepool=broken

# Karpenter 로그에서 provisioning 실패 흔적
kubectl -n kube-system logs deploy/karpenter --tail=100 | grep -i "launch\|instance\|iam"

# Pod은 Pending 상태로 남음
kubectl get pod -n default -l app=trigger-broken
```

**Expected observation** — NodeClaim이 `LaunchFailed` 상태로 나타나며, conditions 메시지에 IAM role 관련 에러가 포함됩니다. Pod은 Pending 상태로 남습니다. 이 시나리오는 `kubectl describe nodeclaim`을 통해 Karpenter의 provisioning 파이프라인(NodeClaim → EC2 RunInstances → kubelet bootstrap → node Ready)에서 어느 단계에서 실패했는지 추적하는 방법을 학습합니다.

**Recovery**

```bash
# broken 리소스 정리
kubectl delete nodepool broken
kubectl delete ec2nodeclass broken
kubectl delete deploy trigger-broken -n default
```

## Step 5 — CAS Removal

[`30-cas-drain-out/cas-removal-checklist.md`](./30-cas-drain-out/cas-removal-checklist.md) 절차를 수행합니다.

## Related Documents

- `docs/week5/3_availability-and-scale.md` — Rate-limit with PDB
- `docs/week5/1_common-failures.md` — Scoping Before Diagnosis
- AWS re:Post — [Troubleshoot cluster scaling with Karpenter](https://repost.aws/knowledge-center/eks-troubleshoot-cluster-scaling-with-karpenter)
