> Cloudnet@EKS Week3

# Lab

Week 3 실습 환경과 스케일링 실습 체크리스트입니다.

## Environment Setup

### Terraform 배포

```bash
# 코드 다운로드
git clone https://github.com/gasida/aews.git
cd aews/3w

# IAM Policy 파일 작성
curl -o aws_lb_controller_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json

# 배포 (~12분)
terraform init && terraform plan
terraform apply -auto-approve

# EKS 자격증명
$(terraform output -raw configure_kubectl)
```

변경점: k8s 1.35, 노드(private subnet, SSM), 권한(EC2 Instance Profile), add-on(metrics-server, external-dns)

### SSM Session Manager

Private subnet 노드에 SSH 없이 접속하는 방법입니다.

```bash
# 관리 대상 인스턴스 확인
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].{Id:InstanceId, Status:PingStatus}" \
  --output table

# CLI로 접속
aws ssm start-session --target <instance-id>
```

### Monitoring Stack

```bash
# kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 80.13.3 -f monitor-values.yaml \
  --create-namespace --namespace monitoring

# EKS 컨트롤 플레인 메트릭 수집을 위한 ClusterRole 권한 추가
kubectl patch clusterrole kube-prometheus-stack-prometheus --type=json -p='[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "verbs": ["get"],
      "apiGroups": ["metrics.eks.amazonaws.com"],
      "resources": ["kcm/metrics", "ksh/metrics"]
    }
  }
]'
```

### eks-node-viewer

노드 allocatable 용량과 Pod request 리소스를 비교 표시합니다. 실제 Pod 리소스 사용량이 아닌 request 합계만 표시합니다.

```bash
# 설치
brew tap aws/tap && brew install eks-node-viewer

# 사용
eks-node-viewer --resources cpu,memory
eks-node-viewer --resources cpu,memory --extra-labels eks-node-viewer/node-age
eks-node-viewer --node-selector "karpenter.sh/registered=true"
```

---

## HPA Hands-on

```bash
# 샘플 앱 배포
kubectl apply -f https://k8s.io/examples/application/php-apache.yaml

# HPA 생성
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10

# 부하 발생
kubectl run -i --tty load-generator --rm --image=busybox:1.28 --restart=Never \
  -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"

# 모니터링
watch -d 'kubectl get hpa,pod; echo; kubectl top pod'

# 정리
kubectl delete deploy,svc,hpa,pod --all
```

## VPA Hands-on

```bash
# CRD + RBAC 설치
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/refs/heads/master/vertical-pod-autoscaler/deploy/vpa-v1-crd-gen.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/refs/heads/master/vertical-pod-autoscaler/deploy/vpa-rbac.yaml

# VPA 컨트롤러 배포
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler/
./hack/vpa-up.sh

# 예제 배포 및 확인
kubectl apply -f examples/hamster.yaml
watch -d "kubectl top pod; echo; kubectl describe pod | grep Requests: -A2"

# 정리
kubectl delete -f examples/hamster.yaml
./hack/vpa-down.sh
```

## CAS Hands-on

```bash
# ASG MaxSize 확장
export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].AutoScalingGroupName" \
  --output text)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name ${ASG_NAME} \
  --min-size 3 --desired-capacity 3 --max-size 6

# CAS 배포
curl -s -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
sed -i '' "s|<YOUR CLUSTER NAME>|myeks|g" cluster-autoscaler-autodiscover.yaml
kubectl apply -f cluster-autoscaler-autodiscover.yaml

# nginx Deployment 배포 (cpu 500m, memory 512Mi)
cat << EOF > nginx.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-to-scaleout
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx-to-scaleout
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 500m
            memory: 512Mi
EOF
kubectl apply -f nginx.yaml

# 스케일 테스트
kubectl scale --replicas=15 deployment/nginx-to-scaleout

# 정리 (10분 후 노드 축소 확인)
kubectl delete -f nginx.yaml
kubectl delete -f cluster-autoscaler-autodiscover.yaml
```

## Karpenter Hands-on

별도 클러스터에서 진행합니다. [Getting Started with Karpenter](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/) 참조.

```bash
# 환경 변수
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.10.0"
export CLUSTER_NAME="${USER}-karpenter-demo"

# CloudFormation + eksctl 클러스터 생성 (~18분)
# Karpenter Helm 설치
# NodePool + EC2NodeClass 생성

# 스케일 테스트
kubectl scale deployment inflate --replicas 5   # 노드 자동 생성
kubectl scale deployment inflate --replicas 1   # Consolidation 동작
kubectl delete deployment inflate               # 빈 노드 삭제

# 정리
helm uninstall karpenter --namespace kube-system
eksctl delete cluster --name "${CLUSTER_NAME}"
aws cloudformation delete-stack --stack-name "Karpenter-${CLUSTER_NAME}"
```

## Fargate Hands-on

Terraform Blueprints 패턴을 사용합니다.

```bash
cd terraform-aws-eks-blueprints/patterns/fargate-serverless
terraform init && terraform apply -auto-approve  # ~13분

# 확인
kubectl get node -owide           # Pod IP = Node IP
kubectl get pod -A -owide         # schedulerName: fargate-scheduler

# 2048 게임 + ALB Ingress
kubectl create ns study-aews
# Deployment + Service + Ingress (target-type: ip) 배포

# 정리
terraform destroy -auto-approve
```

---

## Grafana Dashboards

| Component | Dashboard ID |
|-----------|-------------|
| HPA | 22128, 22251 |
| VPA | 14588 |
| API Server | 15661, 15761 |
| K8s Overview | 15757, 15759, 15762 |
| Karpenter | capacity-dashboard, performance-dashboard |
