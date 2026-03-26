# Lab

실습 스크립트와 매니페스트는 `labs/week2/` 디렉터리를 참고하세요.

---

## Environment Setup

모든 실습에서 공통으로 사용하는 환경 변수를 설정합니다. `N1`/`N2`/`N3`/`N4`(노드 IP), `VPC_ID`, `ACCOUNT_ID` 등이 자동으로 추출됩니다.

```bash
source labs/week2/00_env.sh
```

`MyDomain`과 `MyDnzHostedZoneId`는 `00_env.sh`에서 직접 수정하세요.

---

## Warm Pool Tuning

[VPC CNI의 Warm Pool](./1_vpc-cni.md#warm-pool-environment-variables)은 Pod 생성 시 IP 할당 지연을 줄이기 위해 미리 IP를 확보해 둡니다. `WARM_IP_TARGET`과 `MINIMUM_IP_TARGET`을 변경하면 노드마다 유지하는 여유 IP 수가 달라지는데, 여기서는 실제로 값을 바꾸고 ipamd의 `TotalIPs`가 어떻게 변하는지 확인합니다.

=== "현재 상태 확인"

    각 노드의 ipamd가 현재 몇 개의 IP를 확보하고 있는지 확인합니다.

    ```bash
    eksctl get addon --cluster $CLUSTER_NAME -o json | jq '.[] | select(.Name=="vpc-cni") | .ConfigurationValues'

    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

=== "설정 변경"

    `MINIMUM_IP_TARGET=10`으로 변경하면 Pod이 없어도 각 노드에 최소 10개 IP가 유지됩니다.

    ```bash
    aws eks update-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name vpc-cni \
      --configuration-values '{"env":{"WARM_IP_TARGET":"5","MINIMUM_IP_TARGET":"10"}}' \
      --resolve-conflicts OVERWRITE

    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni
    ```

=== "적용 결과 확인"

    변경 후 `TotalIPs`가 10 이상으로 증가했는지 확인합니다.

    ```bash
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

---

## Pod Networking & SNAT

[Pod Networking](./4_pod-networking.md)에서 다룬 veth pair, `/32` 호스트 라우트, `169.254.1.1` 정적 ARP, policy routing이 실제 노드와 Pod에서 어떻게 설정되어 있는지 확인합니다. SNAT이 동작 중이면 Pod의 아웃바운드 IP가 노드의 퍼블릭 IP와 일치합니다.

=== "Node Network"

    각 노드의 인터페이스, 라우팅 테이블, policy routing 규칙, veth pair 목록을 확인합니다.

    ```bash
    for i in $N1 $N2 $N3; do
      echo "======== node $i ========"
      ssh ec2-user@$i ip addr show
      ssh ec2-user@$i ip route show
      ssh ec2-user@$i ip rule show
      ssh ec2-user@$i ip link show type veth
    done
    ```

=== "Pod Namespace"

    Pod 내부에서 `/32` 주소, `169.254.1.1` default route, 정적 ARP 항목이 설정되어 있는지 확인하고 Pod 간 통신을 테스트합니다.

    ```bash
    kubectl run netshoot --image=nicolaka/netshoot -- sleep infinity
    kubectl wait pod netshoot --for=condition=Ready --timeout=60s

    kubectl exec netshoot -- ip addr show eth0
    kubectl exec netshoot -- ip route show
    kubectl exec netshoot -- arp -a
    # 예상: (169.254.1.1) at <host_veth_MAC> [ether] PERM on eth0

    NGINX_IP=$(kubectl get pod -l app=nginx-deployment -o jsonpath='{.items[0].status.podIP}')
    kubectl exec netshoot -- ping -c 3 $NGINX_IP
    ```

=== "SNAT 확인"

    Pod에서 외부로 나갈 때 소스 IP가 노드 IP로 변환되는지, iptables `AWS-SNAT-CHAIN` 규칙이 존재하는지 확인합니다.

    ```bash
    kubectl exec netshoot -- curl -s https://ipinfo.io/ip
    ssh ec2-user@$N1 curl -s http://169.254.169.254/latest/meta-data/public-ipv4

    ssh ec2-user@$N1 sudo iptables -t nat -S | grep 'A AWS-SNAT-CHAIN'
    ```

---

## Secondary IP Mode — Pod Limit { #pod-capacity }

[Pod Capacity](./3_pod-capacity.md)에서 계산한 t3.medium의 maxPods는 17개입니다. Deployment를 50개로 스케일 아웃하면 3노드 기준 약 45개까지만 Running 상태가 되고 나머지는 IP 부족으로 Pending에 머뭅니다. ipamd의 `TotalIPs == AssignedIPs` 상태를 직접 확인합니다.

=== "스케일 아웃"

    ```bash
    kubectl create deployment nginx-deployment --image=nginx:1.27 --replicas=3
    kubectl scale deployment nginx-deployment --replicas=50
    ```

=== "Pending 원인 확인"

    ```bash
    kubectl describe pod <Pending Pod> | grep Events: -A5
    # Warning  FailedScheduling: Too many pods
    ```

=== "IP 소진 확인"

    3노드 모두 `TotalIPs == AssignedIPs`이면 IP가 완전히 고갈된 상태입니다.

    ```bash
    for i in $N1 $N2 $N3; do
      ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

---

## Prefix Delegation + maxPods=110 { #prefix-delegation }

앞 단계에서 확인한 IP 고갈을 [Prefix Delegation](./2_ip-modes.md#prefix-delegation)으로 해소합니다. ENI 슬롯당 /28(16개 IP)을 할당하면 t3.medium 기준 확보 가능 IP가 15개에서 약 48개로 늘어납니다. 다만 [maxPods는 자동으로 올라가지 않으므로](./3_pod-capacity.md#how-maxpods-is-determined) nodeadm NodeConfig에서 별도로 설정해야 합니다.

EKS-optimized AMI를 그대로 사용하면 EKS가 maxPods를 vCPU 기준으로 덮어쓰므로, SSM Parameter로 동일 AMI ID를 조회하여 `ami_id`에 명시 지정하고 Custom AMI 취급으로 전환해야 NodeConfig 설정이 적용됩니다.

### Prefix Delegation 활성화

활성화 후 각 노드의 ENI에 /28 Prefix가 할당되고, `TotalIPs`가 기존보다 증가하는지 확인합니다.

```bash
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
kubectl rollout status daemonset aws-node -n kube-system

aws ec2 describe-instances \
  --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$CLUSTER_NAME" \
  --query 'Reservations[*].Instances[].{InstanceId:InstanceId, Prefixes:NetworkInterfaces[].Ipv4Prefixes[]}' | jq

for i in $N1 $N2 $N3; do
  echo ">> node $i <<"
  ssh ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
done | grep -E 'node|TotalIPs|AssignedIPs'
```

### pd-110 노드 그룹에서 50개 Pod 배치

`labs/week2/eks.tf`의 `pd-110` 노드 그룹은 Terraform으로 프로비저닝됩니다. SSM Parameter로 조회한 AMI ID를 `ami_id`에 지정하고, `enable_bootstrap_user_data = true`와 `application/node.eks.aws` content_type의 NodeConfig로 `maxPods: 110`을 설정합니다. `challenge=pd-110:NoSchedule` taint으로 기본 워크로드는 이 노드에 스케줄되지 않습니다.

노드가 Ready 상태가 된 뒤 `capacity.pods`가 110인지 확인하고, tolerations와 nodeSelector가 설정된 Deployment 50개를 배치하여 Secondary IP 모드의 한계(17개)를 초과하는지 검증합니다.

=== "노드 확인"

    ```bash
    kubectl get nodes -l challenge=pd-110
    ```

=== "Prefix 할당 확인"

    ```bash
    aws ec2 describe-instances \
      --filters "Name=tag:eks:nodegroup-name,Values=*pd-110*" \
      --query 'Reservations[*].Instances[].{InstanceId:InstanceId, Prefixes:NetworkInterfaces[].Ipv4Prefixes[]}' | jq
    ```

=== "maxPods 확인"

    ```bash
    kubectl get node -l challenge=pd-110 \
      -o jsonpath='{.items[0].status.capacity.pods}'
    # 예상: 110
    ```

=== "50개 Pod 배치"

    ```bash
    kubectl apply -f labs/week2/manifests/pd-110-deployment.yaml

    kubectl get pods -l app=pd-test --field-selector=status.phase=Running | wc -l
    # 예상: 50

    kubectl get pods -l app=pd-test -o wide | head -10
    ```

!!! tip "Community walkthrough"
    [kkamji.net/posts/eks-max-pod-limit](https://kkamji.net/posts/eks-max-pod-limit/)

---

## NLB IP Mode

[AWS LBC](./6_load-balancer.md)를 설치하고 NLB IP mode Service를 배포합니다. IP target type에서는 NLB가 Pod IP를 직접 타겟으로 등록하므로, NodePort를 거치지 않고 Pod 단위로 트래픽이 분배됩니다. 100회 요청을 보내 각 Pod에 약 50:50으로 분산되는지 확인합니다.

```bash
bash labs/week2/01_lbc-install.sh

kubectl apply -f labs/week2/manifests/echo-nlb-ip.yaml
kubectl get svc svc-nlb-ip-type -w

NLB=$(kubectl get svc svc-nlb-ip-type -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in {1..100}; do curl -s $NLB | grep Hostname; done | sort | uniq -c | sort -nr
```

---

## ALB Ingress

2048 게임을 ALB Ingress로 배포합니다. LBC가 Ingress 리소스를 감지하여 ALB를 프로비저닝하고, [TargetGroupBinding](./6_load-balancer.md#alb-ingress)을 통해 Pod IP를 타겟 그룹에 직접 등록합니다.

```bash
kubectl apply -f labs/week2/manifests/game-2048.yaml
kubectl get ingress -n game-2048 -w

kubectl get targetgroupbindings -n game-2048
```

---

## NLB TLS + ExternalDNS { #nlb-tls }

앞 단계에서 배포한 NLB에 ACM 인증서를 연동하여 TLS 종료를 수행합니다. [ExternalDNS](./6_load-balancer.md#externaldns)가 NLB hostname을 감지해 Route53에 A 레코드를 자동 생성하므로, `echo.$MyDomain`으로 HTTPS 접속이 가능해집니다.

### ExternalDNS 설치

```bash
bash labs/week2/03_externaldns.sh
```

### NLB TLS Service 배포

ACM 인증서 ARN을 조회한 뒤, 매니페스트의 placeholder를 치환하여 배포합니다. `aws-load-balancer-ssl-cert`와 `aws-load-balancer-ssl-ports` annotation이 NLB 리스너에 TLS를 설정하고, `external-dns.alpha.kubernetes.io/hostname`이 ExternalDNS에 도메인 등록을 요청합니다.

```bash
export ACM_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='*.$MyDomain'].CertificateArn" \
  --output text)

sed "s|REPLACE_ACM_ARN|$ACM_ARN|; s|REPLACE_MYDOMAIN|$MyDomain|" \
  labs/week2/manifests/echo-nlb-tls.yaml | kubectl apply -f -

kubectl get svc svc-nlb-tls -w
```

### 검증

NLB 리스너에 TLS가 설정되었는지, Route53에 A 레코드가 생성되었는지, HTTPS로 접속이 되는지 순서대로 확인합니다.

```bash
NLB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-default-svcnlbtl')].LoadBalancerArn" \
  --output text)
aws elbv2 describe-listeners --load-balancer-arn $NLB_ARN

aws route53 list-resource-record-sets \
  --hosted-zone-id "$MyDnzHostedZoneId" \
  --query "ResourceRecordSets[?Name == 'echo.${MyDomain}.']" | jq

curl -v https://echo.$MyDomain
```
