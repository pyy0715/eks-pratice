# Lab

실습 스크립트와 매니페스트는 [:octicons-mark-github-16: labs/week2/](https://github.com/pyy0715/eks-pratice/tree/main/labs/week2) 디렉터리를 참고하세요.

---

## Environment Setup

```bash
source labs/week2/00_env.sh
```

`N1`/`N2`/`N3`(default 노드 IP), `N4`(pd-110 노드 IP), `VPC_ID`, `ACCOUNT_ID`, `MyDnzHostedZoneId`, `SSH_KEY`가 자동으로 추출됩니다. `MyDomain`은 `mise.toml`의 `TF_VAR_MyDomain`을 읽으므로 도메인 변경은 해당 파일에서 진행합니다.

---

## Pod Networking & SNAT

각 Pod이 VPC IP를 실제로 어떻게 할당받는지 노드와 Pod 양쪽에서 직접 확인합니다. SNAT이 켜져 있으면 Pod에서 외부로 나가는 트래픽의 출발지 IP가 노드 퍼블릭 IP로 바뀝니다.

=== "Node Network"

    Pod이 실행 중인 노드에서는 veth가 하나 추가되고, 그 Pod IP로 향하는 `/32` 호스트 라우트와 policy routing 규칙이 자동으로 생깁니다.

    ```bash
    for i in $N1 $N2 $N3; do
      echo "======== node $i ========"
      ssh -i $SSH_KEY ec2-user@$i ip addr show
      ssh -i $SSH_KEY ec2-user@$i ip route show
      ssh -i $SSH_KEY ec2-user@$i ip rule show
      ssh -i $SSH_KEY ec2-user@$i ip link show type veth
    done
    ```

    pod이 실행 중인 노드에서 확인해야 할 항목

    ```
    # ip addr show — pod용 veth가 노드 네트워크 네임스페이스에 보여야 함
    5: enib3c1c0d63f5@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
        link-netns cni-0bd98e23-...   ← pod 네트워크 네임스페이스

    # ip route show — pod IP로 향하는 /32 호스트 라우트
    192.168.1.33 dev enib3c1c0d63f5 scope link   ← veth를 통해 pod으로 직접

    # ip rule show — policy routing 규칙 3개
    512:   from all to 192.168.1.33 lookup main       ← pod로 들어오는 트래픽
    1024:  from all fwmark 0x80/0x80 lookup main      ← SNAT 처리된 트래픽
    32765: from 192.168.1.89 lookup 2                 ← secondary ENI 트래픽 → table 2

    # ip link show type veth — pod 없는 노드는 출력 없음
    enib3c1c0d63f5@if3: ...   ← pod 있는 노드에만 존재
    ```

=== "Pod Namespace"

    Pod 안에서는 자신의 IP가 `/32`로 보이고, 모든 트래픽이 `169.254.1.1`이라는 가상 게이트웨이를 거칩니다. 이 주소는 실제로 존재하지 않으며, VPC CNI가 host veth의 MAC을 ARP에 영구 등록해두는 방식으로 동작합니다.

    ```bash
    kubectl run netshoot --image=nicolaka/netshoot -- sleep infinity
    kubectl wait pod netshoot --for=condition=Ready --timeout=60s

    kubectl exec netshoot -- ip addr show eth0
    kubectl exec netshoot -- ip route show
    kubectl exec netshoot -- arp -a
    # 예상: (169.254.1.1) at <host_veth_MAC> [ether] PERM on eth0

    kubectl exec netshoot -- nslookup kubernetes.default
    ```

=== "SNAT"

    Pod에서 외부로 나가는 패킷은 노드의 iptables `AWS-SNAT-CHAIN`을 거쳐 소스 IP가 노드 IP로 바뀝니다.

    ```bash
    # netshoot pod의 아웃바운드 IP 확인
    kubectl exec netshoot -- curl -s https://ipinfo.io/ip

    # netshoot이 올라간 노드의 퍼블릭 IP 확인
    # IMDSv2가 강제된 환경에서는 토큰 없이 169.254.169.254에 접근하면 빈 응답이 오므로 kubectl로 조회
    NODE=$(kubectl get pod netshoot -o jsonpath='{.spec.nodeName}')
    kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}'

    # iptables SNAT 규칙 확인 (N1 기준)
    ssh -i $SSH_KEY ec2-user@$N1 sudo iptables -t nat -S | grep 'A AWS-SNAT-CHAIN'
    ```

    첫 번째 명령이 반환한 IP가 두 번째 명령의 노드 퍼블릭 IP와 일치하면 SNAT이 동작 중입니다.

    iptables 규칙 해석:

    ```
    # VPC 내부(192.168.0.0/16)로 향하는 트래픽 → SNAT 없이 통과 (Pod IP 유지)
    -A AWS-SNAT-CHAIN-0 -d 192.168.0.0/16 ... -j RETURN

    # VPC 외부로 나가는 트래픽 → 노드 IP로 SNAT
    -A AWS-SNAT-CHAIN-0 ! -o vlan+ ... -j SNAT --to-source <노드 IP> --random-fully
    ```

    Pod → Pod 트래픽은 원본 Pod IP 그대로, 인터넷으로 나가는 트래픽만 노드 IP로 변환됩니다.

---

## Warm Pool Tuning

Pod 하나가 생성될 때 VPC secondary IP가 1개 소비됩니다. ipamd는 이 IP를 요청 시점에 발급하면 지연이 생기므로 미리 풀을 채워둡니다. `WARM_IP_TARGET`은 유지할 여유 IP 수, `MINIMUM_IP_TARGET`은 Pod이 없어도 유지할 최솟값입니다. 값을 바꾸면 `TotalIPs`가 어떻게 반응하는지 확인합니다.

=== "현재 상태"

    ```bash
    eksctl get addon --cluster $CLUSTER_NAME -o json | jq '.[] | select(.Name=="vpc-cni") | .ConfigurationValues'

    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh -i $SSH_KEY ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

=== "설정 변경"

    `MINIMUM_IP_TARGET=10`으로 올리면 Pod이 없어도 각 노드가 10개 IP를 들고 있습니다.

    ```bash
    aws eks update-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name vpc-cni \
      --configuration-values '{"env":{"WARM_IP_TARGET":"5","MINIMUM_IP_TARGET":"10"}}' \
      --resolve-conflicts OVERWRITE

    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni
    ```

=== "결과 확인"

    ```bash
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh -i $SSH_KEY ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

=== "초기화"

    다음 섹션에서 IP 소진 시나리오를 정확히 보려면 설정을 기본값으로 되돌립니다.

    ```bash
    aws eks update-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name vpc-cni \
      --configuration-values '{}' \
      --resolve-conflicts OVERWRITE

    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni
    ```

---

## Secondary IP Mode — Pod Limit { #pod-capacity }

t3.medium은 secondary IP를 최대 15개 보유할 수 있고 maxPods는 17입니다. 이미 실행 중인 시스템 Pod(coredns, kube-proxy 등)이 슬롯 일부를 차지하므로, Deployment를 50개로 올리면 일부가 `Too many pods`로 스케줄되지 못합니다. 슬롯이 다 차면 `TotalIPs == AssignedIPs`인 IP 소진 상태도 확인할 수 있습니다.

=== "스케일 아웃"

    netshoot을 먼저 정리하고 시작합니다.

    ```bash
    kubectl delete pod netshoot
    kubectl create deployment nginx-deployment --image=nginx:1.27 --replicas=3
    kubectl scale deployment nginx-deployment --replicas=50
    ```

=== "Pending 원인"

    ```bash
    kubectl describe pod <Pending Pod> | grep Events: -A5
    # Warning  FailedScheduling: Too many pods
    ```

=== "IP 소진 확인"

    ```bash
    for i in $N1 $N2 $N3; do
      echo ">> node $i <<"
      ssh -i $SSH_KEY ec2-user@$i curl -s http://localhost:61679/v1/enis | jq
    done | grep -E 'node|TotalIPs|AssignedIPs'
    ```

---

## Prefix Delegation — Scaling Pod Density { #prefix-delegation }

Secondary IP mode의 한계를 [Prefix Delegation](./2_ip-modes.md#prefix-delegation)으로 해소합니다. ENI 슬롯당 `/28`(16개 IP)을 할당하면 t3.medium 기준 확보 가능 IP가 15개에서 최대 80개로 늘어납니다. 단 [maxPods는 자동으로 올라가지 않으므로](./3_pod-capacity.md#how-maxpods-is-determined) pd-110 노드 그룹에서는 nodeadm NodeConfig로 110을 별도 지정합니다.

### Enable Prefix Delegation

vpc-cni DaemonSet에 `ENABLE_PREFIX_DELEGATION=true`를 설정하면 ipamd는 이후 새로운 IP 요청을 개별 secondary IP 대신 `/28` prefix 단위로 처리합니다. 단 **기존 노드의 ENI에 이미 할당된 secondary IP는 prefix로 교체되지 않습니다.** ipamd는 이미 확보한 warm pool을 그대로 사용하므로, 기존 노드는 재생성해야 처음부터 prefix 모드로 시작합니다.

> "It is highly recommended that you create new node groups to increase the number of available IP addresses rather than doing rolling replacement of existing worker nodes."
>
> — [Prefix Mode for Linux, EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html#_replace_all_nodes_during_the_transition_to_prefix_delegation)

이 실습에서 prefix delegation 동작을 검증하는 대상은 `pd-110` 노드 그룹(1대)입니다. default 노드 그룹 3대는 Pod Limit 실습에서 이미 역할을 마쳤으므로 교체하지 않습니다.

`pd-110` 노드를 scale 0→1로 교체하면 새 노드는 `ENABLE_PREFIX_DELEGATION=true`가 이미 적용된 상태에서 부팅합니다. ipamd가 처음부터 prefix 모드로 IP를 할당하므로 ENI에 `/28` prefix가 붙은 상태로 시작합니다.

nginx를 먼저 정리하고 `ENABLE_PREFIX_DELEGATION`을 활성화한 뒤 노드를 교체합니다.

```bash
kubectl delete deployment nginx-deployment

kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
kubectl rollout status daemonset aws-node -n kube-system

aws eks update-nodegroup-config \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name myeks-pd-110 \
  --scaling-config desiredSize=0,maxSize=2,minSize=0

# 노드가 존재할 때만 삭제 완료를 대기
NODE=$(kubectl get node -l challenge=pd-110 --no-headers -o name 2>/dev/null)
[ -n "$NODE" ] && kubectl wait --for=delete $NODE --timeout=300s

aws eks update-nodegroup-config \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name myeks-pd-110 \
  --scaling-config desiredSize=1,maxSize=2,minSize=1

# EC2가 뜨고 node 오브젝트가 등록될 때까지 대기
until kubectl get node -l challenge=pd-110 --no-headers 2>/dev/null | grep -q .; do
  echo "노드 등록 대기 중..."; sleep 10
done
kubectl wait node -l challenge=pd-110 --for=condition=Ready --timeout=300s

# 재생성된 노드는 IP가 바뀌므로 N4 갱신
N4=$(kubectl get node -l challenge=pd-110 \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
```

노드가 Ready가 되면 ENI에 `/28` prefix가 할당됐는지 확인합니다.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:eks:nodegroup-name,Values=*pd-110*" \
  --query 'Reservations[*].Instances[].{InstanceId:InstanceId, Prefixes:NetworkInterfaces[].Ipv4Prefixes[]}' | jq

ssh -i $SSH_KEY ec2-user@$N4 curl -s http://localhost:61679/v1/enis | \
  jq 'to_entries[] | {slot: .key, TotalIPs: .value.TotalIPs, AssignedIPs: .value.AssignedIPs, prefixes: [.value.ENIs[].AvailableIPv4Cidrs | keys[]]}'
```

### Verify pd-110

`pd-110` 노드 그룹은 동일한 EKS-optimized AMI를 `ami_id`에 명시해 Custom AMI로 취급되도록 했습니다. 덕분에 EKS가 maxPods를 덮어쓰지 않고 nodeadm NodeConfig의 `maxPods: 110`이 그대로 적용됩니다. `challenge=pd-110:NoSchedule` taint로 이 노드에는 toleration이 있는 Pod만 스케줄됩니다.

=== "노드 확인"

    ```bash
    kubectl get nodes -l challenge=pd-110
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

    kubectl get pods -l app=pd-test --no-headers | grep -c Running
    # 예상: 50

    kubectl get pods -l app=pd-test -o wide | head -10
    ```
---

## NLB IP Mode

[AWS LBC](./6_load-balancer.md)를 설치하고 NLB IP mode Service를 배포합니다. NLB가 NodePort를 거치지 않고 Pod IP를 직접 타겟으로 등록하므로, 100회 요청을 보내면 두 Pod에 약 50:50으로 분산됩니다.

```bash
bash labs/week2/01_lbc-install.sh

kubectl apply -f labs/week2/manifests/echo-nlb-ip.yaml
kubectl get svc svc-nlb-ip-type -w

NLB=$(kubectl get svc svc-nlb-ip-type -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in {1..100}; do curl -s $NLB | grep Hostname; done | sort | uniq -c | sort -nr
```

---

## ALB Ingress

2048 게임을 ALB Ingress로 배포합니다. LBC가 Ingress를 감지해 ALB를 프로비저닝하고, [TargetGroupBinding](./6_load-balancer.md#alb-ingress)으로 Pod IP를 타겟 그룹에 직접 등록합니다.

```bash
kubectl apply -f labs/week2/manifests/game-2048.yaml
kubectl get ingress -n game-2048 -w

kubectl get targetgroupbindings -n game-2048
```

ALB 프로비저닝에는 1~2분이 소요됩니다. 출력된 ADDRESS를 통해 정상적으로 작동하는지 브라우저로 접속합니다.

```bash
kubectl get ingress -n game-2048 
```

---

## NLB TLS + ExternalDNS { #nlb-tls }

앞에서 만든 NLB에 ACM 인증서를 붙여 TLS를 종료합니다. [ExternalDNS](./6_load-balancer.md#externaldns)가 NLB hostname을 감지해 Route53에 A 레코드를 자동 등록하므로, `echo.$MyDomain`으로 HTTPS 접속이 가능해집니다.

### Install ExternalDNS

```bash
bash labs/week2/02_externaldns.sh
```

### Deploy NLB TLS Service

`aws-load-balancer-ssl-cert`와 `aws-load-balancer-ssl-ports` annotation이 NLB 리스너에 TLS를 설정하고, `external-dns.alpha.kubernetes.io/hostname`이 ExternalDNS에 도메인 등록을 요청합니다.

```bash
export ACM_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='*.$MyDomain'].CertificateArn" \
  --output text)

sed "s|REPLACE_ACM_ARN|$ACM_ARN|; s|REPLACE_MYDOMAIN|$MyDomain|" \
  labs/week2/manifests/echo-nlb-tls.yaml | kubectl apply -f -

kubectl get svc svc-nlb-tls -w
```

### Verify

NLB 리스너 TLS 설정, Route53 A 레코드 생성, HTTPS 접속 순으로 확인합니다.

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

---

## Cleanup

생성 역순으로 삭제합니다. LBC/ExternalDNS가 관리하는 AWS 리소스(NLB, ALB, Route53 레코드)는 Kubernetes 리소스를 먼저 삭제해야 함께 정리됩니다.

```bash
# NLB TLS + ExternalDNS
kubectl delete svc svc-nlb-tls
kubectl delete -f labs/week2/manifests/game-2048.yaml
kubectl delete -f labs/week2/manifests/echo-nlb-ip.yaml

# NLB/ALB가 완전히 삭제될 때까지 대기
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text

# pd-110 Pod
kubectl delete -f labs/week2/manifests/pd-110-deployment.yaml

# ExternalDNS, LBC
helm uninstall aws-load-balancer-controller -n kube-system
kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json 2>/dev/null || true
```
