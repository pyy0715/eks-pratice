### 실습 환경 배포

- 배포 by terraform *⇒ 변경점 : 1.35(log), 노드(private subnet 배치, SSM) + 권한(ec2 instance profile), add-on(metrics-server, external-dns)*
    
    ```bash
    # 코드 다운로드, 작업 디렉터리 이동
    git clone https://github.com/gasida/aews.git
    cd aews/3w
    
    # IAM Policy 파일 작성
    curl -o aws_lb_controller_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json
    
    cat << EOF > externaldns_controller_policy.json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "route53:ChangeResourceRecordSets",
            "route53:ListResourceRecordSets",
            "route53:ListTagsForResources"
          ],
          "Resource": [
            "arn:aws:route53:::hostedzone/*"
          ]
        },
        {
          "Effect": "Allow",
          "Action": [
            "route53:ListHostedZones"
          ],
          "Resource": [
            "*"
          ]
        }
      ]
    }
    EOF
    
    cat << EOF > cas_autoscaling_policy.json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeScalingActivities",
            "ec2:DescribeImages",
            "ec2:DescribeInstanceTypes",
            "ec2:DescribeLaunchTemplateVersions",
            "ec2:GetInstanceTypesFromInstanceRequirements",
            "eks:DescribeNodegroup"
          ],
          "Resource": ["*"]
        },
        {
          "Effect": "Allow",
          "Action": [
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup"
          ],
          "Resource": ["*"]
        }
      ]
    }
    EOF
    
    **ls *.json**
    *aws_lb_controller_policy.json      cas_autoscaling_policy.json        externaldns_controller_policy.json*
    
    # 배포 : **12분 소요**
    terraform init
    terraform plan
    nohup sh -c "**terraform apply -auto-approve**" > create.log 2>&1 &
    tail -f create.log
    
    # 배포 완료 후 상세 정보 확인
    **cat terraform.tfstate
    terraform show
    terraform state list**
    terraform state show 'module.eks.aws_eks_cluster.this[0]'
    terraform state show 'module.eks.data.tls_certificate.this[0]'
    terraform state show 'module.eks.aws_eks_access_entry.this["cluster_creator"]'
    terraform state show 'module.eks.aws_iam_openid_connect_provider.oidc_provider[0]'
    terraform state show 'module.eks.data.aws_partition.current[0]'
    ...
    terraform state show 'module.eks.time_sleep.this[0]'
    terraform state show 'module.vpc.aws_vpc.this[0]'
    ...
    
    # EKS 자격증명 설정
    **$(terraform output -raw configure_kubectl)**
    **kubectl config rename-context $(cat ~/.kube/config | grep current-context | awk '{print $2}') myeks**
    
    # k8s 1.35 버전 확인
    **kubectl get node -owide**
    *NAME                                                STATUS   ROLES    AGE   VERSION               INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                        KERNEL-VERSION                   CONTAINER-RUNTIME
    ip-192-168-14-130.ap-northeast-2.compute.internal   Ready    <none>   34m   **v1.35.2**-eks-f69f56f   192.168.14.130   <none>        Amazon Linux 2023.10.20260302   6.12.73-95.123.amzn2023.x86_64   containerd://2.2.1+unknown
    ip-192-168-16-49.ap-northeast-2.compute.internal    Ready    <none>   34m   **v1.35.2-**eks-f69f56f   192.168.16.49    <none>        Amazon Linux 2023.10.20260302   6.12.73-95.123.amzn2023.x86_64   containerd://2.2.1+unknown*
    ```
    
- AWS System Manager - Session Manager : 인스턴스 접속
    - [LabGuide - AWS Systems Manager Session Manager](https://www.notion.so/LabGuide-AWS-Systems-Manager-Session-Manager-bf6bac3002044daf8a2b3d5487a2faeb?pvs=21)
    - System Manager - Session Manager 를 통한 인스턴스 접속 - [Install](https://docs.aws.amazon.com/ko_kr/systems-manager/latest/userguide/install-plugin-macos-overview.html)
        
        ![방안1 : 웹 관리콘솔에서 접속](attachment:a0e9bdf0-5d58-4a12-adae-5ac8386aa06e:image.png)
        
        방안1 : 웹 관리콘솔에서 접속
        
        ```bash
        # SSM 관리 대상 인스턴스 목록 조회
        **aws ssm describe-instance-information \
          --query "InstanceInformationList[*].{InstanceId:InstanceId, Status:PingStatus, OS:PlatformName}" \
          --output text** # table
        *i-0a6db521a84f6ea1f     Amazon Linux    Online
        i-02e04862dcf98dabd     Amazon Linux    Online*
        
        # session-manager-plugin 설치
        # https://docs.aws.amazon.com/ko_kr/systems-manager/latest/userguide/install-plugin-macos-overview.html
        brew install --cask session-manager-plugin # macOS - Disable date: 2026-09-01
        
        # 방안2 : session-manager-plugin 을 통한 인스턴스 접속!
        **aws ssm start-session --target *i-0a6db521a84f6ea1f***
        --------------------------------------------------
        *Starting session with SessionId: admin-or2bs6qcpf3kk79oriyg7r4oii
        sh-5.2$ **bash**
        [ssm-user@ip-192-168-14-130 bin]$ **whoami**
        ssm-user
        [ssm-user@ip-192-168-14-130 bin]$ **sudo su -**
        [root@ip-192-168-14-130 ~]# **whoami**
        root
        [root@ip-192-168-14-130 ~]# **ss -tnp**
        State Recv-Q Send-Q           Local Address:Port             Peer Address:Port Process                                    
        ESTAB 0      2076            192.168.14.130:49390            43.202.70.20:443   users:(("ssm-agent-worke",pid=1971,fd=24))
        ESTAB 0      0               192.168.14.130:38556             43.202.73.3:443   users:(("ssm-agent-worke",pid=1971,fd=17))
        ESTAB 0      0               192.168.14.130:53750           43.202.72.118:443   users:(("ssm-session-wor",pid=8063,fd=15))
        ...
        [root@ip-192-168-14-130 ~]# **exit***
        --------------------------------------------------
        
        ```
        
        ![System Manager - Session Manager](attachment:e80a930a-9a86-4b18-8fd5-b01f792b4dfa:image.png)
        
        System Manager - Session Manager
        
    - **동작 구성**
        
        ![](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/8d0ddb0c-4f4c-45c9-9ebc-2ebcc7562e38/Untitled.png)
        
        ![systems manager 와 session manager 접속 지점은 AWS 공인 IP 대역](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/de115757-dda6-4a45-81bc-039f436a9188/_2020-08-21__5.44.24.png)
        
        systems manager 와 session manager 접속 지점은 AWS 공인 IP 대역
        
    - **Web_Console 과 AWS_CLI 로 Session Manager 접근 시 동작**
        
        ![](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/f1562d12-ed01-44f9-bcef-2c8ea871c4cf/Untitled.png)
        
        - IAM 사용자가 `Web Shell` 이나 `AWS CLI` (aws ssm start-session...) 등으로 접근 시 **Step3) Web Shell** 처럼 동작합니다.
            - 이미 IAM 사용자로 AWS 인증이 되었으므로 `Web Shell` `AWS CLI` 접속 시 **추가 인증이 없습니다.**
            - Systems Manager 설정으로 IAM 사용자의 Session Logging (세션 활동 로깅)이 가능합니다.
            - 접속하는 [대상 노드]에 대해서만 Port Forwarding 이 가능합니다.
    
- eks addon 확인 : metrics-server , external-dns
    
    ![image.png](attachment:17f90e64-b1d2-4889-9994-a01251123c73:image.png)
    
    ```bash
    # 현재 eks 에서 addon 확인
    **aws eks list-addons --cluster-name myeks | jq**
    {
      "addons": [
        "coredns",
        "external-dns",
        "kube-proxy",
        "metrics-server",
        "vpc-cni"
      ]
    }
    
    # metrics-server 관련 정보 확인
    kubectl get deploy -n kube-system metrics-server
    kubectl describe deploy -n kube-system metrics-server
    kubectl get pod -n kube-system -l app.kubernetes.io/instance=metrics-server -owide
    kubectl get pdb -n kube-system metrics-server
    kubectl get svc,ep -n kube-system metrics-server
    
    # metrics-server api 관련 정보 확인
    kubectl api-resources | grep -i metrics
    kubectl explain NodeMetrics
    kubectl explain PodMetrics
    kubectl api-versions | grep metrics
    kubectl get apiservices |egrep '(AVAILABLE|metrics)'
    
    # 노드/파드 cpu/mem 자원 시용 확인
    kubectl top node
    kubectl top pod -A
    kubectl top pod -n kube-system --sort-by='cpu'
    kubectl top pod -n kube-system --sort-by='memory'
    
    # external-dns  관련 정보 확인
    kubectl get deploy,pod,svc,ep,sa -n external-dns 
    **kubectl get sa -n external-dns external-dns -o yaml** *# eks add-on 중 external-dns 는 helm 설치로 보임!*
    *...
      labels:
        app.kubernetes.io/instance: external-dns
        app.kubernetes.io/**managed-by: Helm**
    ...*
    
    **helm list -A**
    *NAME    NAMESPACE       REVISION        UPDATED STATUS  CHART   APP VERSION*
    
    **kubectl describe deploy -n external-dns external-dns**
    *...
    Labels:             app.kubernetes.io/instance=external-dns
                        app.kubernetes.io/managed-by=Helm
                        app.kubernetes.io/name=external-dns
                        app.kubernetes.io/version=0.19.0
                        helm.sh/chart=external-dns-1.19.0
    ...
        Args:
          --log-level=info
          --log-format=text
          --interval=1m
          **--source=service
          --source=ingress
          --policy=upsert-only***  # 레코드 업데이트 정책 : upsert-only - 생성/수정만 하고 삭제는 수동
          *--registry=txt
          --txt-owner-id=myeks
          **--provider=aws**
    ...*
    ```
    
- `도전과제` 테라폼으로 eks addon 에 **external-dns 배포 시, extraArgs** 에 `policy=sync` 적용 해보기
    
    ```bash
        external-dns = {
          most_recent = true
          configuration_values = jsonencode({
            txtOwnerId = var.ClusterBaseName
            policy     = "sync"
          })
    ```
    
- AWS LBC 설치 - [Helm](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller) *⇒ 4주차에는 terraform 으로 배포 예정*
    
    ```bash
    # Helm Chart Repository 추가
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    # Helm Chart - AWS Load Balancer Controller 설치 : EC2 Instance Profile(IAM Role)을 파드가 IMDS 통해 획득 가능!
    **helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.1.0 \
      --set clusterName=myeks**
    
    # 확인
    **helm list -n kube-system**
    **kubectl get pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller**
    **kubectl logs -n kube-system deployment/aws-load-balancer-controller -f**
    
    ```
    
- (참고) awscli 파드에서, 해당 노드(EC2)의 IMDS 정보 확인 : AWS CLI v2 파드 사용 - [Docs](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/getting-started-docker.html) , [공식이미지링크](https://hub.docker.com/r/amazon/aws-cli) *⇒ 자세한 내용은 4주차에서 다룸*
    
    ```bash
    # awscli 파드 생성
    cat <<EOF | kubectl apply -f -
    apiVersion: apps/v1
    kind: **Deployment**
    metadata:
      name: awscli-pod
    spec:
      **replicas: 2**
      selector:
        matchLabels:
          app: awscli-pod
      template:
        metadata:
          labels:
            app: awscli-pod
        spec:
          containers:
          - name: awscli-pod
            image: **amazon/aws-cli**
            command: ["tail"]
            args: ["-f", "/dev/null"]
          terminationGracePeriodSeconds: 0
    EOF
    
    # 파드 생성 확인
    kubectl get pod -owide
    
    # 파드 이름 변수 지정
    APODNAME1=$(kubectl get pod -l app=awscli-pod -o jsonpath="{.items[0].metadata.name}")
    APODNAME2=$(kubectl get pod -l app=awscli-pod -o jsonpath="{.items[1].metadata.name}")
    echo $APODNAME1, $APODNAME2
    
    # awscli 파드에서 EC2 InstanceProfile(IAM Role)의 ARN 정보 확인
    kubectl exec -it $APODNAME1 -- aws sts get-caller-identity --query Arn
    kubectl exec -it $APODNAME2 -- aws sts get-caller-identity --query Arn
    
    # awscli 파드에서 EC2 InstanceProfile(IAM Role)을 사용하여 AWS 서비스 정보 확인 >> 별도 IAM 자격 증명이 없는데 어떻게 가능한 것일까요?
    # > 최소권한부여 필요!!! >>> 보안이 허술한 아무 컨테이너나 탈취 시, IMDS로 해당 노드의 IAM Role 사용 가능!
    kubectl exec -it $APODNAME1 -- **aws ec2 describe-instances --region ap-northeast-2 --output table --no-cli-pager**
    kubectl exec -it $APODNAME2 -- **aws ec2 describe-vpcs --region ap-northeast-2 --output table --no-cli-pager**
     
    # EC2 메타데이터 확인 : IDMSv1은 Disable, IDMSv2 활성화 상태, IAM Role - [링크](https://docs.aws.amazon.com/ko_kr/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)
    kubectl exec -it $APODNAME1 -- bash 
    -----------------------------------
    **아래부터는 파드에 bash shell 에서 실행**
    curl -s http://169.254.169.254/ -v
    ...
    
    # Token 요청 
    curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" ; echo
    curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" ; echo
    
    # Token을 이용한 IMDSv2 사용
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    echo $TOKEN
    curl -s -H "X-aws-ec2-metadata-token: $TOKEN" –v http://169.254.169.254/ ; echo
    curl -s -H "X-aws-ec2-metadata-token: $TOKEN" –v http://169.254.169.254/latest/ ; echo
    **curl -s -H "X-aws-ec2-metadata-token: $TOKEN" –v http://169.254.169.254/latest/meta-data/iam/security-credentials/ ; echo**
    
    # 위에서 출력된 IAM Role을 아래 입력 후 확인
    curl -s -H "X-aws-ec2-metadata-token: $TOKEN" –v http://169.254.169.254/latest/meta-data/iam/security-credentials/**myeks-ng-1
    {
      "Code" : "Success",
      "LastUpdated" : "2023-05-27T05:08:07Z",
      "Type" : "AWS-HMAC",
      "AccessKeyId" : "ASIA5ILF2FJI****REDACTED****",
      "SecretAccessKey" : "****REDACTED****",
      "Token" : "****REDACTED****",
      "Expiration" : "2023-05-27T11:09:07Z"
    }**
    ## 출력된 정보는 AWS API를 사용할 수 있는 어느곳에서든지 Expiration 되기전까지 사용 가능
    
    # 파드에서 나오기
    **exit**
    ---
    
    # 실습 완료 후 삭제
    **kubectl delete deploy awscli-pod**
    
    ```
    
    - 워커 노드에 연결된 IAM 역할(정책)을 관리콘솔에서 확인해보자
    
    ![https://sharing-for-us.tistory.com/39](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/2872f88d-a0bd-4d05-8aba-274ecc4c3e4d/Untitled.png)
    
    https://sharing-for-us.tistory.com/39
    
- eks-node-viewer 설치 : 노드 할당 가능 용량과 요청 request 리소스 표시, 실제 파드 리소스 사용량 X - [Github](https://github.com/awslabs/eks-node-viewer)
    - 설치
        
        ```bash
        # macOS 설치
        brew tap aws/tap
        brew install eks-node-viewer
        
        # Windows 에 WSL2 (Ubuntu) 설치
        sudo apt install golang-go
        go install github.com/awslabs/eks-node-viewer/cmd/eks-node-viewer@latest  # 설치 시 2~3분 정도 소요
        echo 'export PATH="$PATH:/root/go/bin"' >> /etc/profile
        
        ---
        # 아래처럼 바이너리파일 다운로드 후 사용 가능 : 버전 체크
        wget -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v**0.7.4**/eks-node-viewer_Linux_x86_64
        chmod +x eks-node-viewer
        sudo mv -v eks-node-viewer /usr/local/bin
        ```
        
    - 사용
        
        ```bash
        # [신규 터미널] 모니터링 : eks 자격증명 필요
        
        # Standard usage
        **eks-node-viewer**
        
        # Display both CPU and Memory Usage
        eks-node-viewer --resources cpu,memory
        **eks-node-viewer --resources cpu,memory** --extra-labels eks-node-viewer/node-age
        
        ****# Display extra labels, i.e. AZ : node 에 labels 사용 가능
        **eks-node-viewer --extra-labels topology.kubernetes.io/zone
        eks-node-viewer --extra-labels kubernetes.io/arch**
        
        # Sort by CPU usage in descending order
        **eks-node-viewer --node-sort=eks-node-viewer/node-cpu-usage=dsc**
        
        # Karenter nodes only
        **eks-node-viewer --node-selector "karpenter.sh/***provisioner-name***"**
        
        # Specify a particular AWS profile and region
        AWS_PROFILE=myprofile AWS_REGION=us-west-2
        
        **Computed Labels** : --extra-labels
        # eks-node-viewer/node-age - Age of the node
        **eks-node-viewer --extra-labels** eks-node-viewer/node-age
        **eks-node-viewer --extra-labels** topology.kubernetes.io/zone,eks-node-viewer/node-age
        
        # eks-node-viewer/node-ephemeral-storage-usage - Ephemeral Storage usage (requests)
        **eks-node-viewer --extra-labels** eks-node-viewer/node-ephemeral-storage-usage
        
        # eks-node-viewer/node-cpu-usage - CPU usage (requests)
        **eks-node-viewer --extra-labels** eks-node-viewer/node-cpu-usage
        ****
        # eks-node-viewer/node-memory-usage - Memory usage (requests)
        **eks-node-viewer --extra-labels** eks-node-viewer/node-memory-usage
        ****
        # eks-node-viewer/node-pods-usage - Pod usage (requests)
        **eks-node-viewer --extra-labels** eks-node-viewer/node-pods-usage
        ```
        
    - **동작**
        - It displays the scheduled pod resource requests vs the allocatable capacity on the node.
        - It does not look at the actual pod resource usage.
        - Node마다 할당 가능한 용량과 스케줄링된 POD(컨테이너)의 Resource 중 request 값을 표시한다.
        - 실제 POD(컨테이너) 리소스 사용량은 아니다. /pkg/model/pod.go 파일을 보면 컨테이너의 request 합을 반환하며, init containers는 미포함
        - https://github.com/awslabs/eks-node-viewer/blob/main/pkg/model/pod.go#L82
            
            ```bash
            // **Requested returns the sum of the resources requested by the pod**. **This doesn't include any init containers** as we
            // are interested in the steady state usage of the pod
            func (p *Pod) Requested() v1.ResourceList {
            	p.mu.RLock()
            	defer p.mu.RUnlock()
            	requested := v1.ResourceList{}
            	for _, c := range p.pod.Spec.Containers {
            		for rn, q := range c.Resources.Requests {
            			existing := requested[rn]
            			existing.Add(q)
            			requested[rn] = existing
            		}
            	}
            	requested[v1.ResourcePods] = resource.MustParse("1")
            	return requested
            }
            ```
            
    
- kube-ops-view 배포 + ALB Ingress(MyDomain, HTTPS → HTTP)
    
    ```bash
    # kube-ops-view : **NodePort 나 LoadBalancer Type 필요 없음!**
    helm repo add geek-cookbook https://geek-cookbook.github.io/charts/
    helm install kube-ops-view geek-cookbook/kube-ops-view --version 1.2.2 --set service.main.type=**ClusterIP** --set env.TZ="Asia/Seoul" --namespace kube-system
    
    # 확인
    kubectl get deploy,pod,svc,ep -n kube-system -l app.kubernetes.io/instance=kube-ops-view
    
    # 사용 리전의 인증서 ARN 변수 지정 : 정상 상태 확인(만료 상태면 에러 발생!)
    CERT_ARN=$(aws acm list-certificates --query 'CertificateSummaryList[].CertificateArn[]' --output text)
    echo $CERT_ARN
    
    # 자신의 공인 도메인 변수 지정
    **MyDomain=<자신의 공인 도메인>**
    echo $MyDomain
    
    *MyDomain=gasida.link
    echo $MyDomain*
    
    # kubeopsview 용 Ingress 설정 : group 설정으로 1대의 ALB를 여러개의 ingress 에서 공용 사용
    cat <<EOF | kubectl apply -f -
    apiVersion: networking.k8s.io/v1
    kind: **Ingress**
    metadata:
      annotations:
        alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
        **alb.ingress.kubernetes.io/group.name: study**
        alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
        alb.ingress.kubernetes.io/**load-balancer-name: myeks-ingress-alb**
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/**ssl-redirect: "443"**
        alb.ingress.kubernetes.io/success-codes: 200-399
        alb.ingress.kubernetes.io/target-type: ip
      labels:
        app.kubernetes.io/name: kubeopsview
      name: kubeopsview
      namespace: kube-system
    spec:
      **ingressClassName: alb**
      rules:
      - host: **kubeopsview.$MyDomain**
        http:
          paths:
          - backend:
              service:
                name: kube-ops-view
                port:
                  number: 8080
            path: /
            pathType: Prefix
    EOF
    
    # service, ep, ingress 확인
    kubectl get ingress,svc,ep -n kube-system
    
    # Kube Ops View 접속 정보 확인 
    echo -e "Kube Ops View URL = https://kubeopsview.$MyDomain/#scale=1.5"
    open "https://kubeopsview.$MyDomain/#scale=1.5" # macOS
    
    ~~# (참고) 삭제 시~~
    ~~kubectl delete ingress -n kube-system kubeopsview~~
    ```
    
- kube-prometheus-stack 배포 - [Link](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack) + ALB Ingress(MyDomain, HTTPS → HTTP)
    
    ![[15761 API Server] eks api server 인스턴스 IP 기준 2대가 기본 형상!](attachment:5a9adcbd-29dc-4f65-83ec-067799a97e70:image.png)
    
    [15761 API Server] eks api server 인스턴스 IP 기준 2대가 기본 형상!
    
    ![eks api server 인스턴스 기본 2대! https://docs.aws.amazon.com/ko_kr/eks/latest/best-practices/control-plane.html
    ***EKS**는 AWS 리전 내 개별 가용 영역(AZs)에서 **최소 2개의 API 서버 노드**를 실행합니다 → 본문 내용 중 참고*](attachment:085a1592-2325-4dff-9765-e78f6a2dc889:d8c6b4bd-d1c0-463a-ba8e-bb06967ec73c.png)
    
    eks api server 인스턴스 기본 2대! https://docs.aws.amazon.com/ko_kr/eks/latest/best-practices/control-plane.html
    ***EKS**는 AWS 리전 내 개별 가용 영역(AZs)에서 **최소 2개의 API 서버 노드**를 실행합니다 → 본문 내용 중 참고*
    
    - Helm 설치
        
        ```bash
        # repo 추가
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        
        # helm values 파일 생성 : additionalScrapeConfigs 는 아래 설명
        cat <<EOT > monitor-values.yaml
        **prometheus:**
          prometheusSpec:
            podMonitorSelectorNilUsesHelmValues: false
            serviceMonitorSelectorNilUsesHelmValues: false
            **additionalScrapeConfigs:**
              **# apiserver metrics**
              - job_name: apiserver-metrics
                kubernetes_sd_configs:
                - role: endpoints
                scheme: https
                tls_config:
                  ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                  insecure_skip_verify: true
                bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                relabel_configs:
                - source_labels:
                    [
                      __meta_kubernetes_namespace,
                      __meta_kubernetes_service_name,
                      __meta_kubernetes_endpoint_port_name,
                    ]
                  action: keep
                  regex: default;kubernetes;https
              **# Scheduler metrics**
              - job_name: 'ksh-metrics'
                kubernetes_sd_configs:
                - role: endpoints
                metrics_path: /apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics
                scheme: https
                tls_config:
                  ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                  insecure_skip_verify: true
                bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                relabel_configs:
                - source_labels:
                    [
                      __meta_kubernetes_namespace,
                      __meta_kubernetes_service_name,
                      __meta_kubernetes_endpoint_port_name,
                    ]
                  action: keep
                  regex: default;kubernetes;https
              **# Controller Manager metrics**
              - job_name: 'kcm-metrics'
                kubernetes_sd_configs:
                - role: endpoints
                metrics_path: /apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics
                scheme: https
                tls_config:
                  ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                  insecure_skip_verify: true
                bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                relabel_configs:
                - source_labels:
                    [
                      __meta_kubernetes_namespace,
                      __meta_kubernetes_service_name,
                      __meta_kubernetes_endpoint_port_name,
                    ]
                  action: keep
                  regex: default;kubernetes;https
        
          # Enable vertical pod autoscaler support for prometheus-operator
          #**verticalPodAutoscaler**:
          #  enabled: true
        
          **ingress:**
            enabled: true
            ingressClassName: alb
            hosts: 
              - **prometheus.$MyDomain**
            paths: 
              - /*
            annotations:
              alb.ingress.kubernetes.io/scheme: internet-facing
              alb.ingress.kubernetes.io/target-type: ip
              alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
              alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
              alb.ingress.kubernetes.io/success-codes: 200-399
              alb.ingress.kubernetes.io/load-balancer-name: myeks-ingress-alb
              **alb.ingress.kubernetes.io/group.name: study**
              alb.ingress.kubernetes.io/ssl-redirect: '443'
        
        **grafana:**
          defaultDashboardsTimezone: Asia/Seoul
          adminPassword: **prom-operator**
        
          **ingress:**
            enabled: true
            ingressClassName: alb
            hosts: 
              - **grafana.$MyDomain**
            paths: 
              - /*
            annotations:
              alb.ingress.kubernetes.io/scheme: internet-facing
              alb.ingress.kubernetes.io/target-type: ip
              alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
              alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
              alb.ingress.kubernetes.io/success-codes: 200-399
              alb.ingress.kubernetes.io/load-balancer-name: myeks-ingress-alb
              **alb.ingress.kubernetes.io/group.name: study**
              alb.ingress.kubernetes.io/ssl-redirect: '443'
        
        kubeControllerManager:
          enabled: false
        kubeEtcd:
          enabled: false
        kubeScheduler:
          enabled: false
        prometheus-windows-exporter:
          prometheus:
            monitor:
              enabled: false
        EOT
        cat monitor-values.yaml
        
        # 배포
        **helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 80.13.3 \
        -f monitor-values.yaml --create-namespace --namespace monitoring**
        
        # 확인
        helm list -n monitoring
        kubectl get sts,ds,deploy,pod,svc,ep,ingress -n monitoring
        kubectl get prometheus,servicemonitors -n monitoring
        kubectl get crd | grep monitoring
        kubectl get-all -n monitoring  # kubectl krew install get-all
        
        # 프로메테우스 버전 확인
        **kubectl exec -it sts/prometheus-kube-prometheus-stack-prometheus -n monitoring -c prometheus -- prometheus --version**
        *prometheus, version 3.1.0 (branch: HEAD, revision: 7086161a93b262aa0949dbf2aba15a5a7b13e0a3)*
        ...
        
        # 프로메테우스 웹 접속
        echo -e "https://prometheus.$MyDomain"
        open "https://prometheus.$MyDomain" # macOS
        
        # 그라파나 웹 접속 : admin / **prom-operator**
        echo -e "https://grafana.$MyDomain"
        open "https://grafana.$MyDomain" # macOS
        
        ~~# (참고) 업그레이드 및 삭제 시
        helm upgrade -i kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 80.13.3 \
        -f monitor-values.yaml --create-namespace --namespace monitoring
        
        helm uninstall -n monitoring kube-prometheus-stack~~
        ```
        
        ![프로메테우스 웹 접속 후 Target 확인](attachment:556d8817-c111-4548-9f8e-a3e256aad7da:image.png)
        
        프로메테우스 웹 접속 후 Target 확인
        
    - EKS 컨트롤 플레인 원시 지표(메트릭)을 Prometheus 형식으로 가져오기 - [Docs](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/view-raw-metrics.html) , [Blog](https://devfloor9.github.io/engineering-playbook/docs/eks-best-practices/control-plane-scaling/eks-control-plane-crd-scaling)
        
        ```bash
        ┌─────────────────────────────────────────────────────────────────────┐
        │                 EKS Control Plane Observability                     │
        ├──────────────────┬──────────────────┬────────────────┬──────────────┤
        │ ① CloudWatch     │ ② **Prometheus**    │ ③ Control      │ ④ Cluster   │
        │    Vended Metrics│    **Metrics**       │    Plane       │    Insights  │
        │                  │    **Endpoint**      │    Logging     │              │
        ├──────────────────┼──────────────────┼────────────────┼──────────────┤
        │ AWS/EKS 네임스페이스│ **KCM/KSH**/etcd     │ API/Audit/     │ Upgrade      │
        │ (자동, 무료)       │ (Prometheus      │ Auth/CM/Sched  │ Readiness    │
        │                  │  호환 K8s API)    │ (CloudWatch    │ Health Issues│
        │                  │                  │  Logs)         │ Addon Compat │
        ├──────────────────┼──────────────────┼────────────────┼──────────────┤
        │ v1.28+ 자동       │ v1.28+ 수동       │ 모든 버전        │ 모든 버전 자동 │
        └──────────────────┴──────────────────┴────────────────┴──────────────┘
        ```
        
        ```bash
        # helm values 파일 생성 : additionalScrapeConfigs 다시 살펴보기!
        **helm get values -n monitoring kube-prometheus-stack**
        *...
              job_name: **ksh-metrics**
              kubernetes_sd_configs:
              - role: endpoints
              metrics_path: **/apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics**
        ...*
        
        # Metrics.eks.amazonaws.com의 컨트롤 플레인 지표 가져오기 : kube-scheduler , kube-controller-manager 지표
        kubectl get --raw "/apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics"
        kubectl get --raw "/apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics"
        kubectl get svc,ep -n kube-system eks-extension-metrics-api
        **kubectl get apiservices |egrep '(AVAILABLE|metrics)'**
        *NAME                              SERVICE                                 AVAILABLE   AGE
        v1.metrics.eks.amazonaws.com      kube-system/eks-extension-metrics-api   True        75m
        v1beta1.metrics.k8s.io            kube-system/metrics-server              True        68m*
        
        # 프로메테우스 파드 정보 확인
        **kubectl describe pod -n monitoring prometheus-kube-prometheus-stack-prometheus-0  | grep 'Service Account'**
        *Service Account:  kube-prometheus-stack-prometheus*
        
        # 해당 SA에 권한이 없음!
        kubectl rbac-tool lookup kube-prometheus-stack-prometheus # kubectl krew install rbac-tool
        **kubectl rolesum kube-prometheus-stack-prometheus -n monitoring** # kubectl krew install rolesum
        ...
        *Policies:
        • [CRB] */kube-prometheus-stack-prometheus ⟶  [CR] */kube-prometheus-stack-prometheus
          Resource                         Name  Exclude  Verbs  G L W C U P D DC  
          endpoints                        [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖   
          endpointslices.discovery.k8s.io  [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖   
          ingresses.networking.k8s.io      [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖   
          nodes                            [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖   
          nodes/metrics                    [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖   
          pods                             [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖   
          services                         [*]     [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖*  
        
        # 클러스터롤에 권한 추가
        kubectl get clusterrole kube-prometheus-stack-prometheus
        **kubectl patch clusterrole kube-prometheus-stack-prometheus --type=json -p='[
          {
            "op": "add",
            "path": "/rules/-",
            "value": {
              "verbs": ["get"],
              "apiGroups": ["metrics.eks.amazonaws.com"],
              "resources": ["kcm/metrics", "ksh/metrics"]
            }
          }
        ]'**
        
        **kubectl rolesum kube-prometheus-stack-prometheus -n monitoring**
        *...
        • [CRB] */kube-prometheus-stack-prometheus ⟶  [CR] */kube-prometheus-stack-prometheus
          Resource                               Name  Exclude  Verbs  G L W C U P D DC  
          ...
          **kcm.metrics.eks.amazonaws.com/metrics**  [*]     [-]     [-]   ✔ ✖ ✖ ✖ ✖ ✖ ✖ ✖   
          **ksh.metrics.eks.amazonaws.com/metrics**  [*]     [-]     [-]   ✔ ✖ ✖ ✖ ✖ ✖ ✖ ✖   
          ...*
        ```
        
        ![image.png](attachment:921d42d2-2dfc-4832-931e-6abeca0c7dfd:image.png)
        
    - **그라파나 Dashboard 추가 :** **15661**(직접 import 추가), **15761**, 15757, 15759. 15762 - [Github](https://github.com/dotdc/grafana-dashboards-kubernetes)
        
        ```bash
        # 대시보드 다운로드
        curl -O https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/refs/heads/master/dashboards/k8s-system-api-server.json
        
        # sed 명령어로 uid 일괄 변경 : 기본 데이터소스의 uid 'prometheus' 사용
        ****sed -i -e 's/${DS_PROMETHEUS}/**prometheus**/g' **k8s-system-api-server.json**
        
        # my-dashboard 컨피그맵 생성 : Grafana 포드 내의 사이드카 컨테이너가 grafana_dashboard="1" 라벨 탐지!
        kubectl create configmap my-dashboard **--from-file=k8s-system-api-server.json** -n monitoring
        kubectl label configmap my-dashboard **grafana_dashboard="1"** -n monitoring
        
        # 대시보드 경로에 추가 확인
        **kubectl exec -it -n monitoring deploy/kube-prometheus-stack-grafana -- ls -l /tmp/dashboards**
        
        ```
        
    - *~~AWS targetgroupbindings 출력 버그?~~ ⇒ 동작에는 문제 없음!*
        
        ![CleanShot 2025-03-01 at 22.37.05.png](attachment:7436dc51-0495-445b-8871-3cf3b7a7aded:CleanShot_2025-03-01_at_22.37.05.png)
        
        ![image.png](attachment:77d307a6-f764-459f-90f3-a1813fa8b512:image.png)
        
        ```bash
        #
        **kubectl get targetgroupbindings.elbv2.k8s.aws -A**
        *NAMESPACE     NAME                               SERVICE-NAME                       SERVICE-PORT   TARGET-TYPE   AGE
        kube-system   k8s-kubesyst-kubeopsv-c5f22f90ce   kube-ops-view                      8080           ip            173m
        monitoring    k8s-monitori-kubeprom-7604023ad5   kube-prometheus-stack-grafana      80             ip            163m
        monitoring    k8s-monitori-kubeprom-c3573d4bda   kube-prometheus-stack-prometheus   9090           ip            163m*
        
        #
        **kubectl describe targetgroupbindings.elbv2.k8s.aws -n monitoring**
        ...
        Spec:
          Ip Address Type:  ipv4
          Networking:
            Ingress:
              From:
                Security Group:
                  Group ID:  sg-0ec90ea2a51ad8da5
              Ports:
                **Port:      9090**
                Protocol:  TCP
          Service Ref:
            Name:            kube-prometheus-stack-prometheus
            **Port:            9090**
          Target Group ARN:  arn:aws:elasticloadbalancing:ap-northeast-2:911283464785:targetgroup/k8s-monitori-kubeprom-ba27a9dbfd/d1fd208921747c04
          Target Type:       ip
          Vpc ID:            vpc-048f2b4557b09f5b4
        ...
        
        #
        **kubectl describe targetgroupbindings.elbv2.k8s.aws -n kube-system**
        ...
        Spec:
          Ip Address Type:  ipv4
          Networking:
            Ingress:
              From:
                Security Group:
                  Group ID:  sg-0ec90ea2a51ad8da5
              Ports:
                **Port:      http**
                Protocol:  TCP
          Service Ref:
            Name:            kube-ops-view
            **Port:            8080**
          Target Group ARN:  arn:aws:elasticloadbalancing:ap-northeast-2:911283464785:targetgroup/k8s-kubesyst-kubeopsv-a484a0c5ec/314038dae8b4cb05
          Target Type:       ip
          Vpc ID:            vpc-048f2b4557b09f5b4
        ...
        
        ****kubectl get pod -n kube-system -l app.kubernetes.io/instance=kube-ops-view -o json | jq
        **kubectl get pod -n kube-system -l app.kubernetes.io/instance=kube-ops-view -o jsonpath="{.items[0].spec.containers[0].ports[0]}" | jq**
        {
          "**containerPort**": **8080**,
          "**name**": "**http**",
          "protocol": "TCP"
        }
        
        ```
        
- `도전과제` kube-prometheus-stack helm 배포 시, **eks etcd 메트릭**을 가져올 수 있게 프로메테우스에 설정해보기
- `도전과제` kube-prometheus-stack helm 배포 시, eks controlplane metrics 가져올 수 있게 프로메테우스에 **clusterrole 추가 해서 배포**되게 해보기
- `도전과제` kube-prometheus-stack helm 배포 시, **그라파나에 대시보드(kcm, scheduler 등) 링크를 추가**해서 배포되게 해보기

### EKS 관리형 노드 그룹

- [K8S 파드 스케줄링 실습 가이드](https://www.notion.so/K8S-2c550aec5edf808595fcc5c726050855?pvs=21)
- 관리형 노드 그룹 **myeks-ng-1** 확인 : **온디멘드**
    
    ```bash
    # 노드 정보 확인
    **kubectl get nodes --label-columns eks.amazonaws.com/nodegroup,kubernetes.io/arch,eks.amazonaws.com/capacityType**
    *NAME                                                STATUS   ROLES    AGE    VERSION               NODEGROUP    ARCH    CAPACITYTYPE
    ip-192-168-16-236.ap-northeast-2.compute.internal   Ready    <none>   51m    v1.35.2-eks-f69f56f   myeks-ng-1   amd64   ON_DEMAND
    ip-192-168-23-145.ap-northeast-2.compute.internal   Ready    <none>   51m    v1.35.2-eks-f69f56f   myeks-ng-1   amd64   ON_DEMAND*
    
    # 관리형 노드 그룹 ****확인
    **eksctl get nodegroup --cluster myeks**
    *CLUSTER NODEGROUP       STATUS  CREATED                 MIN SIZE        MAX SIZE        DESIRED CAPACITY        INSTANCE TYPE   IMAGE ID                ASG NAME                                                TYPE
    myeks   myeks-ng-1      ACTIVE  2026-03-25T12:11:31Z    1               4               2                       t3.medium       AL2023_x86_64_STANDARD  eks-myeks-ng-1-c0ce9274-159c-bf55-e5f2-820078f71e89     managed*
    
    **aws eks describe-nodegroup --cluster-name myeks --nodegroup-name myeks-ng-1 | jq**
    ...
    ```
    
    ![image.png](attachment:f0d3e128-c2b9-4bd6-82cc-f103d3e03e2f:image.png)
    
- 관리형 노드 그룹 **myeks-ng-2 :** AWS Graviton (**ARM**) Instance - [Link](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/graviton/)
    - AWS Graviton (ARM) Instance 소개 - [Github](https://github.com/aws/aws-graviton-getting-started) , [Blog](https://symplesims.github.io/aws/modernization/2024/02/29/experience-application-modernization-w-graviton.html)
        - AWS Graviton 프로세서 : **64-bit Arm 프로세서** 코어 기반의 AWS 커스텀 반도체 ⇒ **20~40% 향상된 가격대비 성능**
        - 추천 정보
            - AWS Graviton을 이용해 더 적은 비용으로 더 높은 성능을 내보기 - [Youtube](https://www.youtube.com/watch?v=JlCjK0NGQSo)
            - 하이퍼커넥트의 AWS Graviton 이전을 위한 거대한 도전과 여정 - [Youtube](https://www.youtube.com/watch?v=AE1QHyFnZsw)
        
        ![image.png](attachment:eacf90af-0edd-4e74-a15a-6ba2f028870e:image.png)
        
    - 관리형 노드 그룹 **myeks-ng-2 :** 신규 노드 그룹 추가 생성 by 테라폼
        
        ```bash
        **# 아래 코드 부분 주석 해제 후 테라폼 배포 실행!**
        terraform plan
        **terraform apply -auto-approve**
        
        # The aws eks wait nodegroup-active command can be used to wait until a specific EKS node group is active and ready for use.
        **aws eks wait nodegroup-active --cluster-name myeks --nodegroup-name myeks-ng-2**
        
        ```
        
        ```bash
            # 2nd 노드 그룹 (추가)
            secondary = {
              name            = "${var.ClusterBaseName}**-ng-2**"
              use_name_prefix = false
              ami_type        = "**AL2023_ARM_64_STANDARD**" # https://docs.aws.amazon.com/ko_kr/tnb/latest/ug/node-eks-managed-node.html#node-eks-managed-node-capabilities
              instance_types  = ["**t4g.medium**"] 
              desired_size    = 1
              max_size        = 1
              min_size        = 1
              disk_size        = var.WorkerNodeVolumesize
              subnets          = module.vpc.private_subnets
              vpc_security_group_ids = [aws_security_group.node_group_sg.id]
        
              iam_role_name    = "${var.ClusterBaseName}**-ng-2**"
              iam_role_use_name_prefix = false
              # 학습을 위해 EC2 Instance Profile 에 필요한 IAM Role 추가
              iam_role_additional_policies = {
                "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy" = aws_iam_policy.aws_lb_controller_policy.arn
                "${var.ClusterBaseName}ExternalDNSPolicy" = aws_iam_policy.external_dns_policy.arn
                AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
              }
              
              # 노드에 배포된 파드에서 C2 Instance Profile 사용을 위해 EC2 메타데이터 호출을 위한 hop limit 2 증가
              metadata_options = {
                http_endpoint               = "enabled"
                http_tokens                 = "required"   # IMDSv2 강제
                http_put_response_hop_limit = 2            # hop limit = 2
              }
        
              # node label
              labels = {
                tier = "secondary"
              }
        
              # node taint
              taints = {
                frontend = {
                  key    = "cpuarch"
                  value  = "arm64"
                  effect = "NO_EXECUTE"
                }
              }
        
              # AL2023 전용 userdata 주입
              cloudinit_pre_nodeadm = [
                {
                  content_type = "text/x-shellscript"
                  content      = <<-EOT
                    #!/bin/bash
                    echo "Starting custom initialization..."
                    dnf update -y
                    dnf install -y tree bind-utils tcpdump nvme-cli links sysstat ipset htop
                    echo "Custom initialization completed."
                  EOT
                }
              ]
            }
        ```
        
    - 확인
        
        ```bash
        # 신규 노드 그룹 생성 확인
        **kubectl get nodes --label-columns eks.amazonaws.com/nodegroup,kubernetes.io/arch,eks.amazonaws.com/capacityType**
        *NAME                                                STATUS   ROLES    AGE    VERSION               NODEGROUP    ARCH    CAPACITYTYPE
        ip-192-168-16-236.ap-northeast-2.compute.internal   Ready    <none>   51m    v1.35.2-eks-f69f56f   myeks-ng-1   amd64   ON_DEMAND
        ip-192-168-23-145.ap-northeast-2.compute.internal   Ready    <none>   51m    v1.35.2-eks-f69f56f   myeks-ng-1   amd64   ON_DEMAND
        ip-192-168-20-75.ap-northeast-2.compute.internal    Ready    <none>   6m2s   v1.35.2-eks-f69f56f   **myeks-ng-2   arm64**   ON_DEMAND*
        
        **eksctl get nodegroup --cluster myeks**
        *CLUSTER NODEGROUP       STATUS  CREATED                 MIN SIZE        MAX SIZE        DESIRED CAPACITY        INSTANCE TYPE   IMAGE ID                ASG NAME                                                TYPE
        myeks   myeks-ng-1      ACTIVE  2026-03-25T12:11:31Z    1               4               2                       t3.medium       AL2023_x86_64_STANDARD  eks-myeks-ng-1-c0ce9274-159c-bf55-e5f2-820078f71e89     managed
        myeks   myeks-ng-2      ACTIVE  2026-03-25T12:57:15Z    1               1               1                       t4g.medium      AL2023_ARM_64_STANDARD  eks-myeks-ng-2-2ece9289-05f1-8823-26f5-10a335cadc1d     managed*
        
        **aws eks describe-nodegroup --cluster-name myeks --nodegroup-name myeks-ng-2 | jq
        aws eks describe-nodegroup --cluster-name myeks --nodegroup-name myeks-ng-2 | jq .nodegroup.taints**
        *[
          {
            "key": "cpuarch",
            "value": "arm64",
            "effect": "**NO_EXECUTE**"  #* 스케줄링 하지 않음 - **노드상에서 조건이 일치하지 않는 파드는 동작X. Taint 설정 전 이미 스케줄링된 파드(Toleration 미설정된)도 Evict됨.**
          *}
        ]*
        
        # k8s 노드 정보 확인
        kubectl get node -l kubernetes.io/arch=arm64
        kubectl get node -l tier=secondary -owide
        **kubectl describe node -l tier=secondary | grep -i taint**
        *Taints:             cpuarch=arm64:NoExecute*
        
        ****# SSM 관리 대상 인스턴스 목록 조회
        **aws ec2 describe-instances \
          --instance-ids $(aws ssm describe-instance-information \
            --query "InstanceInformationList[?PingStatus=='Online'].InstanceId" \
            --output text) \
          --query "Reservations[].Instances[].{
            InstanceId:InstanceId,
            Type:InstanceType,
            Arch:Architecture,
            AMI:ImageId,
            State:State.Name
          }" \
          --output table**
          *-------------------------------------------------------------------------------------
        |                                 DescribeInstances                                 |
        +------------------------+---------+-----------------------+----------+-------------+
        |           AMI          |  Arch   |      InstanceId       |  State   |    Type     |
        +------------------------+---------+-----------------------+----------+-------------+
        |  ami-013c8233b9e7c0812 |  x86_64 |  i-04a7732338201b363  |  running |  t3.medium  |
        |  ami-013c8233b9e7c0812 |  x86_64 |  i-0deedd65e2ad0664d  |  running |  t3.medium  |
        |  ami-0e5921d9c9934648c |  arm64  |  i-0bca7e84729c95af6  |  running |  t4g.medium |
        +------------------------+---------+-----------------------+----------+-------------+*
        
        **# 인스턴스 접속 후 arch 확인** 
        **aws ssm start-session --target *i-08b07a8575315a3a7***
        --------------------------------------------------
        sh-5.2$ **arch**
        *aarch64*
        ****--------------------------------------------------
        ```
        
    - 해당 노드에 샘플 파드 배포 1
        
        ```bash
        # sample-app 디플로이먼트 배포
        cat <<EOF | kubectl apply -f -
        apiVersion: apps/v1
        kind: **Deployment**
        metadata:
          name: sample-app
          labels:
            app: sample-app
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: sample-app
          template:
            metadata:
              labels:
                app: sample-app
            spec:
              nodeSelector:
                kubernetes.io/arch: arm64
              containers:
              - name: sample-app
                image: **nginx:alpine**
                ports:
                - containerPort: 80
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
        EOF
        
        # 확인
        **kubectl describe pod -l app=sample-app**
        
        **# 파드에 tolerations 설정으로 배치 실행!**
        cat <<EOF | kubectl apply -f -
        apiVersion: apps/v1
        kind: **Deployment**
        metadata:
          name: sample-app
          labels:
            app: sample-app
        spec:
          **replicas: 1**
          selector:
            matchLabels:
              app: sample-app
          template:
            metadata:
              labels:
                app: sample-app
            spec:
              nodeSelector:
                kubernetes.io/arch: arm64
              **tolerations:
              - key: "cpuarch"
                operator: "Equal"
                value: "arm64"
                effect: "NoExecute"**
              containers:
              - name: sample-app
                image: **nginx:alpine**
                ports:
                - containerPort: 80
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
        EOF
        **kubectl get events -w --sort-by '.lastTimestamp'**
        
        # 확인
        **kubectl get pod -l app=sample-app**
        **kubectl describe pod -l app=sample-app**
        
        **# 삭제
        kubectl delete deploy sample-app**
        ```
        
    - 해당 노드에 샘플 파드 배포 2
        
        ```bash
        # 샘플 애플리케이션 배포
        **cat << EOF | kubectl apply -f -**
        apiVersion: apps/v1
        kind: **Deployment**
        metadata:
          name: mario
          labels:
            app: mario
        **spec**:
          replicas: 1
          selector:
            matchLabels:
              app: mario
          **template**:
            metadata:
              labels:
                app: mario
            spec:
              nodeSelector:
                kubernetes.io/arch: **arm64**
              **tolerations:
              - key: "cpuarch"
                operator: "Equal"
                value: "arm64"
                effect: "NoExecute"**
              containers:
              - name: mario
                image: **pengbai/docker-supermario**
        EOF
        **kubectl get events -w --sort-by '.lastTimestamp'**
        
        # 확인
        **kubectl get pod -l app=mario
        kubectl stern -l app=mario**            
        *+ mario-7cb97489b5-ftcbf › mario
        mario-7cb97489b5-ftcbf mario exec /usr/local/tomcat/bin/catalina.sh: exec format error*
        
        **# 해당 노드에 ssm 접속 후 local 에 컨테이너 이미지 매니페스트 정보에서 cpu arch 정보 확인 명령 추가해두자!
        
        # 삭제
        kubectl delete deploy mario**
        ```
        
        ![https://hub.docker.com/r/pengbai/docker-supermario/tags](attachment:deca0b3b-463d-4846-a4e4-6e638ee9a5a8:image.png)
        
        https://hub.docker.com/r/pengbai/docker-supermario/tags
        
    - 테라폼 코드에 관리형 노드 그룹 **myeks-ng-2** 주석 설정 후 `terraform apply -auto-approve`
- 관리형 노드 그룹 **myeks-ng-3 : Spot** instances 노드 그룹 (managed-spot) - [Link](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/spot/) , [Blog](https://aws.amazon.com/ko/blogs/containers/amazon-eks-now-supports-provisioning-and-managing-ec2-spot-instances-in-managed-node-groups/)
    - Spot instances 노드 그룹 활용 소개
        - AWS 고객이 EC2 여유 용량 풀을 활용하여 **엄청난 할인**으로 EC2 인스턴스를 실행할 수 있습니다.
        - EC2에 용량이 다시 필요할 때 2분 알림으로 Spot Instances를 중단할 수 있습니다.
        - Kubernetes 워커 노드로 Spot Instances를 사용하는 것은 상태 비저장 API 엔드포인트, 일괄 처리, ML 학습 워크로드, Apache Spark를 사용한 빅데이터 ETL, 대기열 처리 애플리케이션, CI/CD 파이프라인과 같은 워크로드에 매우 인기 있는 사용 패턴입니다.
        - 예를 들어 Kubernetes에서 상태 비저장 API 서비스를 실행하는 것은 Spot Instances를 워커 노드로 사용하기에 매우 적합합니다. Pod를 우아하게 종료할 수 있고 Spot Instances가 중단되면 다른 워커 노드에서 대체 Pod를 예약할 수 있기 때문입니다.
        
        ![https://aws.amazon.com/ko/blogs/containers/amazon-eks-now-supports-provisioning-and-managing-ec2-spot-instances-in-managed-node-groups/](attachment:214d5a88-de83-427a-81c0-6fda5bfeb469:image.png)
        
        https://aws.amazon.com/ko/blogs/containers/amazon-eks-now-supports-provisioning-and-managing-ec2-spot-instances-in-managed-node-groups/
        
    - (참고) Instance type diversification - [Link](https://github.com/aws/amazon-ec2-instance-selector) , [Docs](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/spot/instance-diversification)
        
        ```bash
        # ec2-instance-selector 설치
        curl -Lo ec2-instance-selector https://github.com/aws/amazon-ec2-instance-selector/releases/download/v2.4.1/ec2-instance-selector-`uname | tr '[:upper:]' '[:lower:]'`-amd64 && chmod +x ec2-instance-selector
        mv ec2-instance-selector /usr/local/bin/
        **ec2-instance-selector** --version
        
        # 적절한 인스턴스 스펙 선택을 위한 도구 사용
        **ec2-instance-selector --vcpus 2 --memory 4 --gpus 0 --current-generation -a x86_64 --deny-list 't.*' --output table-wide**
        Instance Type   VCPUs   Mem (GiB)  Hypervisor  Current Gen  Hibernation Support  CPU Arch  Network Performance  ENIs    GPUs    GPU Mem (GiB)  GPU Info  On-Demand Price/Hr  Spot Price/Hr (30d avg)
        -------------   -----   ---------  ----------  -----------  -------------------  --------  -------------------  ----    ----    -------------  --------  ------------------  -----------------------
        c5.large        2       4          nitro       true         true                 x86_64    Up to 10 Gigabit     3       0       0              none      $0.096              $0.02837
        c5a.large       2       4          nitro       true         false                x86_64    Up to 10 Gigabit     3       0       0              none      $0.086              $0.04022
        c5d.large       2       4          nitro       true         true                 x86_64    Up to 10 Gigabit     3       0       0              none      $0.11               $0.03265
        c6i.large       2       4          nitro       true         true                 x86_64    Up to 12.5 Gigabit   3       0       0              none      $0.096              $0.03425
        c6id.large      2       4          nitro       true         true                 x86_64    Up to 12.5 Gigabit   3       0       0              none      $0.1155             $0.03172
        c6in.large      2       4          nitro       true         true                 x86_64    Up to 25 Gigabit     3       0       0              none      $0.1281             $0.04267
        c7i-flex.large  2       4          nitro       true         true                 x86_64    Up to 12.5 Gigabit   3       0       0              none      $0.09576            $0.02872
        c7i.large       2       4          nitro       true         true                 x86_64    Up to 12.5 Gigabit   3       0       0              none      $0.1008             $0.02977
        
        #Internally ec2-instance-selector is making calls to the **DescribeInstanceTypes** for the specific region and filtering the instances based on the criteria selected in the command line, in our case we filtered for instances that meet the following criteria:
        - Instances with no GPUs
        - of x86_64 Architecture (no ARM instances like A1 or m6g instances for example)
        - Instances that have 2 vCPUs and 4 GB of RAM
        - Instances of current generation (4th gen onwards)
        - Instances that don’t meet the regular expression t.* to filter out burstable instance types
        ```
        
    - 관리형 노드 그룹 **myeks-ng-3 :** 신규 노드 그룹 추가 생성 by 테라폼
        
        ```bash
        **# 아래 코드 부분 주석 해제 후 테라폼 배포 실행!**
        terraform plan
        **terraform apply -auto-approve**
        
        # The aws eks wait nodegroup-active command can be used to wait until a specific EKS node group is active and ready for use.
        **aws eks wait nodegroup-active --cluster-name myeks --nodegroup-name myeks-ng-3**
        
        ```
        
        ```bash
            third = {
              name            = "${var.ClusterBaseName}**-ng-3**"
              use_name_prefix = false
              ami_type        = "AL2023_x86_64_STANDARD"
              # 스팟 인스턴스 설정의 핵심
              **capacity_type   = "SPOT"
              instance_types  = ["c5a.large", "c6a.large", "t3a.large", "t3a.medium"]**
              desired_size    = 1
              max_size        = 1
              min_size        = 1
              disk_size        = var.WorkerNodeVolumesize
              subnets          = module.vpc.private_subnets
              vpc_security_group_ids = [aws_security_group.node_group_sg.id]
        
              iam_role_name    = "${var.ClusterBaseName}**-ng-3**"
              iam_role_use_name_prefix = false
              # 학습을 위해 EC2 Instance Profile 에 필요한 IAM Role 추가
              iam_role_additional_policies = {
                "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy" = aws_iam_policy.aws_lb_controller_policy.arn
                "${var.ClusterBaseName}ExternalDNSPolicy" = aws_iam_policy.external_dns_policy.arn
                AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
              }
              
              # 노드에 배포된 파드에서 C2 Instance Profile 사용을 위해 EC2 메타데이터 호출을 위한 hop limit 2 증가
              metadata_options = {
                http_endpoint               = "enabled"
                http_tokens                 = "required"   # IMDSv2 강제
                http_put_response_hop_limit = 2            # hop limit = 2
              }
        
              # node label
              labels = {
                tier = "third"
              }
        
              # AL2023 전용 userdata 주입
              cloudinit_pre_nodeadm = [
                {
                  content_type = "text/x-shellscript"
                  content      = <<-EOT
                    #!/bin/bash
                    echo "Starting custom initialization..."
                    dnf update -y
                    dnf install -y tree bind-utils tcpdump nvme-cli links sysstat ipset htop
                    echo "Custom initialization completed."
                  EOT
                }
              ]
            }
        ```
        
        - (TS) 혹시 처음 **Spot 인스턴스 생성 시 에러 발생** 시
            
            ```bash
            # EC2 Spot Fleet의 service-linked-role 생성 확인 : 만들어있는것을 확인하는 거라 아래 에러 출력이 정상!
            # 목적 : AWS 서비스(여기서는 Spot)가 사용자를 대신하여 다른 AWS 리소스(EC2 등)를 조작할 수 있는 권한을 가진 전용 역할을 만듭
            # 이유 : 스팟 인스턴스를 요청하면, AWS 내부 시스템이 알아서 인스턴스를 띄우고 회수해야 합니다. 이 역할을 수행하려면 AWSServiceRoleForEC2Spot이라는 이름의 역할이 계정에 반드시 존재해야 합니다.
            # If the role has already been successfully created, you will see:
            # An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForEC2Spot has been taken in this account, please try a different suffix.
            **aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true**
            
            ```
            
        
    - 확인
        
        ![https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/spot/create-spot-capacity](attachment:ed8d234f-36b7-44a3-b700-4859fb161e95:image.png)
        
        https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/spot/create-spot-capacity
        
        ```bash
        # 신규 노드 그룹 생성 확인
        **kubectl get nodes --label-columns eks.amazonaws.com/nodegroup,kubernetes.io/arch,eks.amazonaws.com/capacityType**
        **kubectl get nodes -L eks.amazonaws.com/capacityType**
        *NAME                                                STATUS   ROLES    AGE     VERSION               CAPACITYTYPE
        ip-192-168-15-173.ap-northeast-2.compute.internal   Ready    <none>   3m20s   v1.35.2-eks-f69f56f   SPOT
        ip-192-168-16-236.ap-northeast-2.compute.internal   Ready    <none>   132m    v1.35.2-eks-f69f56f   ON_DEMAND
        ip-192-168-23-145.ap-northeast-2.compute.internal   Ready    <none>   132m    v1.35.2-eks-f69f56f   ON_DEMAND*
        
        **eksctl get nodegroup --cluster myeks**
        *CLUSTER NODEGROUP       STATUS  CREATED                 MIN SIZE        MAX SIZE        DESIRED CAPACITY        INSTANCE TYPE                                   IMAGE ID                ASG NAME                                  TYPE
        myeks   myeks-ng-1      ACTIVE  2026-03-25T12:11:31Z    1               4               2                       t3.medium                                       AL2023_x86_64_STANDARD  eks-myeks-ng-1-c0ce9274-159c-bf55-e5f2-820078f71e89        managed
        myeks   myeks-ng-3      ACTIVE  2026-03-25T14:21:03Z    1               1               1                       c5a.large,c6a.large,t3a.large,t3a.medium        AL2023_x86_64_STANDARD  eks-myeks-ng-3-fcce92af-5fca-7f66-2ad3-997d4920638b        managed*
        
        **aws eks describe-nodegroup --cluster-name myeks --nodegroup-name myeks-ng-3 | jq
        aws eks describe-nodegroup --cluster-name myeks --nodegroup-name myeks-ng-3 | jq .nodegroup.instanceTypes**
        *[
          "c5a.large",
          "c6a.large",
          "t3a.large",
          "t3a.medium"
        ]*
        
        kubectl get node -l tier=third
        kubectl get node -l eks.amazonaws.com/capacityType=SPOT
        **kubectl describe node -l eks.amazonaws.com/capacityType=SPOT**
        
        **eks-node-viewer --extra-labels eks-node-viewer/node-age**
        *ip-192-168-21-223.ap-northeast-2.compute.internal cpu ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  18% (9 pods)  t3.medium/$0.0520  On-Demand - Ready 110m
        ip-192-168-18-42.ap-northeast-2.compute.internal  cpu ███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░  19% (10 pods) t3.medium/$0.0520  On-Demand - Ready 110m
        ip-192-168-14-46.ap-northeast-2.compute.internal  cpu ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   8% (3 pods)  t3a.medium/$0.0142 **Spot**      - Ready 83s*
        
        # 스팟 EC2 인스턴스 확인
        aws ec2 describe-instances \
          --filters "Name=instance-lifecycle,Values=spot" \
          --query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,AZ:Placement.AvailabilityZone,State:State.Name}" \
          --output table
        
        # 스팟 요청 확인 : Spot Instance Request
        aws ec2 describe-spot-instance-requests \
          --query "SpotInstanceRequests[].{ID:SpotInstanceRequestId,State:State,Type:Type,InstanceId:InstanceId}" \
          --output table
        
        # Spot 가격 조회 : ~~# t3a.large t3a.medium~~
        aws ec2 describe-spot-price-history \
          --instance-types **c6a.large c5a.large** \
          --product-descriptions "Linux/UNIX" \
          --max-items 100 \
          --query "SpotPriceHistory[].{Type:InstanceType,Price:SpotPrice,AZ:AvailabilityZone,Time:Timestamp}" \
          --output table
        
        ```
        
        ![EC2 → 인스턴스 → 스팟 요청](attachment:99e6c3d8-00a9-45d9-8798-50515c70b259:image.png)
        
        EC2 → 인스턴스 → 스팟 요청
        
    - 해당 노드에 샘플 파드 배포
        
        ```bash
        # 파드 배포
        cat <<EOF | kubectl apply -f -
        apiVersion: v1
        kind: Pod
        metadata:
          name: **busybox**
        spec:
          terminationGracePeriodSeconds: 3
          containers:
          - name: busybox
            image: busybox
            command:
            - "/bin/sh"
            - "-c"
            - "while true; do date >> /home/pod-out.txt; cd /home; sync; sync; sleep 10; done"
          **nodeSelector:
            eks.amazonaws.com/capacityType: SPOT**
        EOF
        
        # 파드가 배포된 노드 정보 확인
        kubectl get pod -owide
        
        # 삭제
        **kubectl delete pod busybox**
        
        ```
        
    - 테라폼 코드에 관리형 노드 그룹 **myeks-ng-3** 주석 설정 후 `terraform apply -auto-approve`
    - Interruption Handling in EKS managed node groups with Spot capacity : 곧 자리 뺏길 것 같으니까 미리 다른 자리로 옮겨! - [Link](https://catalog.us-east-1.prod.workshops.aws/workshops/c4ab40ed-0299-4a4e-8987-35d90ba5085e/en-US/40-ec2-spot-instances/3-spotlifecycle)
        
        ![image.png](attachment:98c52394-6c01-4b32-bc9d-3c95b756b551:image.png)
        
        - Spot 중단을 처리하기 위해 AWS Node Termination Handler와 같은 클러스터에 **추가 자동화 도구를 설치할 필요가 없습**니다. **관리형 노드 그룹**은 사용자를 대신하여 **Amazon EC2 Auto Scaling 그룹을 구성하**고 다음과 같은 방식으로 **Spot 중단을 처리**합니다. To handle Spot interruptions, you do not need to install any extra automation tools on the cluster such as the AWS Node Termination Handler. A managed node group configures an Amazon EC2 Auto Scaling group on your behalf and handles the Spot interruption in following manner:
            - Amazon EC2 **Spot 용량 재조정**은 Amazon EKS가 Spot 노드를 우아하게 비우고 재조정하여 Spot 노드가 중단 위험이 높을 때 애플리케이션 중단을 최소화할 수 있도록 활성화됩니다.
                - Amazon EC2 **Spot Capacity Rebalancing** is enabled so that Amazon EKS can gracefully drain and rebalance your Spot nodes to minimize application disruption when a Spot node is at elevated risk of interruption. For more information, see [Amazon EC2 Auto Scaling Capacity Rebalancing](https://docs.aws.amazon.com/autoscaling/ec2/userguide/capacity-rebalance.html)  in the Amazon EC2 Auto Scaling User Guide.
            - 교체 Spot 노드가 부트스트랩되고 Kubernetes에서 Ready 상태가 되면 Amazon EKS는 재조정 권장 사항을 수신한 Spot 노드를 **cordons**하고 **drains**합니다. Spot 노드를 **cordons**하면 노드가 예약 불가능으로 표시되고 kube-scheduler가 해당 노드에서 새 포드를 예약하지 않습니다.
                - When a **replacement Spot node is bootstrapped and in the Ready** state on Kubernetes, Amazon EKS **cordons** and **drains** the Spot node that received the rebalance recommendation. Cordoning the Spot node ensures that the node is marked as **unschedulable** and **kube-schedule**r will **not schedule** any new pods on it. It also removes it from its list of healthy, active Spot nodes. [Draining](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)  the Spot node ensures that running pods are evicted gracefully.
            - 교체 Spot 노드가 준비 상태가 되기 전에 Spot 2분 중단 알림이 도착하면 Amazon EKS는 재균형 권장 사항을 받은 Spot 노드의 드레이닝을 시작합니다.
                - If a Spo**t two-minute interruption notice arrives** before the replacement Spot node is in a Ready state, Amazon EKS starts draining the Spot node that received the rebalance recommendation.
        - 이 프로세스는 **Spot 중단이 도착할 때까지 교체 Spot 노드를 기다리는 것을 피하고, 대신 사전에 교체 노드를 조달하여 보류 중인 Pod의 스케줄링 시간을 최소화**하는 데 도움이 됨. This process avoids waiting for replacement Spot node till Spot interruption arrives, instead it procures replacement in advance and helps in minimizing the scheduling time for pending pods.

        
### HPA - Horizontal Pod Autoscaler
- 부하 발생을 위한 클라이언트용 파드 배포 및 반복 호출
    
    ```bash
    # curl 파드 배포
    **cat <<EOF | kubectl apply -f -**
    apiVersion: v1
    kind: Pod
    metadata:
      **name: curl**
    spec:
      containers:
      - name: curl
        image: **curlimages/curl:latest**
        command: ["sleep", "3600"]
      restartPolicy: Never
    **EOF**
    
    # 서비스명으로 호출 : 'kubectl exec -it deploy/php-apache -- top' 에 CPU 증가 확인!
    kubectl exec -it curl -- curl php-apache
    kubectl exec -it curl -- curl php-apache
    
    # 서비스명으로 반복 호출 
    kubectl exec curl -- sh -c 'while true; do curl -s php-apache; **sleep 1**; done'
    kubectl exec curl -- sh -c 'while true; do curl -s php-apache; **sleep 0.5**; done'
    kubectl exec curl -- sh -c 'while true; do curl -s php-apache; **sleep 0.1**; done'
    ****kubectl exec curl -- sh -c 'while true; do curl -s php-apache; **sleep 0.01**; done'
    *혹은 병렬 호출 (부하 테스트 느낌, 5개 worker 동시 요청)
    kubectl exec -it curl -- sh -c '
    for i in $(seq 1 5); do
      while true; do curl -s php-apache & sleep 1; done &
    done
    wait'*
    ```
    
- HPA 정책 생성 및 부하 발생 후 파드 오토 스케일링 확인
    - 증가 시 기본 대기 시간(30초), 감소 시 기본 대기 시간(5분) → 조정 가능
    
    ```bash
    # Create the HorizontalPodAutoscaler : requests.cpu=200m - [알고리즘](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details)
    # Since each pod requests **200 milli-cores** by kubectl run, this means an average CPU usage of **100 milli-cores**.
    **cat <<EOF | kubectl apply -f -**
    apiVersion: **autoscaling/v2**
    kind: **HorizontalPodAutoscaler**
    metadata:
      name: **php-apache**
    **spec**:
      **scaleTargetRef**:
        apiVersion: apps/v1
        kind: Deployment
        name: php-apache
      minReplicas: 1
      maxReplicas: 10
      **metrics**:
      - type: **Resource**
        resource:
          name: **cpu**
          target:
            averageUtilization: **50**
            type: **Utilization**
    **EOF**
    혹은
    kubectl **autoscale** deployment php-apache **--cpu-percent=50** --min=1 --max=10
    
    # 확인
    **kubectl describe hpa**
    ...
    Metrics:                                               ( current / target )
      resource cpu on pods  (as a percentage of request):  0% (1m) / 50%
    Min replicas:                                          1
    Max replicas:                                          10
    Deployment pods:                                       1 current / 1 desired
    ...
    
    # HPA 설정 확인
    **kubectl get hpa php-apache -o yaml** | kubectl neat
    spec: 
      minReplicas: 1               # [4] 또는 최소 1개까지 줄어들 수도 있습니다
      maxReplicas: 10              # [3] 포드를 최대 10개까지 늘립니다
      **scaleTargetRef**: 
        apiVersion: apps/v1
        kind: **Deployment**
        name: **php-apache**           # [1] php-apache 의 자원 사용량에서
      **metrics**: 
      - type: **Resource**
        resource: 
          name: **cpu**
          target: 
            type: **Utilization**
            **averageUtilization**: 50  # [2] CPU 활용률이 50% 이상인 경우
    
    # 반복 접속 1 (**파드1** IP로 접속) >> 아래 각각 실행 후 최대 증가 갯수 확인 해보기! ***스터디 시간 상 sleep 0.01 바로 실행!***
    kubectl exec curl -- sh -c 'while true; do curl -s php-apache; sleep 0.5; done'
    kubectl exec curl -- sh -c 'while true; do curl -s php-apache; sleep 0.1; done'
    **kubectl exec curl -- sh -c 'while true; do curl -s php-apache; sleep 0.01; done'**
    
    # 반복 접속 2 (서비스명 도메인으로 **파드들 분산** 접속) >> 증가 확인(몇개까지 증가되는가? 그 이유는?) 후 중지
    ## >> **[scale back down] 중지 5분 후** 파드 갯수 감소 확인
    # Run this in a separate terminal
    # so that the load generation continues and you can carry on with the rest of the steps
    kubectl run -i --tty load-generator --rm --image=**busybox**:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
    
    # Horizontal Pod Autoscaler Status Conditions
    **kubectl describe hpa
    ...**
    Events:
      Type    Reason             Age    From                       Message
      ----    ------             ----   ----                       -------
      Normal  SuccessfulRescale  13m    horizontal-pod-autoscaler  New size: 2; reason: cpu resource utilization (percentage of request) above target
      Normal  SuccessfulRescale  11m    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
      Normal  SuccessfulRescale  11m    horizontal-pod-autoscaler  New size: 6; reason: cpu resource utilization (percentage of request) above target
      Normal  SuccessfulRescale  10m    horizontal-pod-autoscaler  New size: 8; reason: cpu resource utilization (percentage of request) above target
      Normal  SuccessfulRescale  5m35s  horizontal-pod-autoscaler  New size: 7; reason: All metrics below target
      Normal  SuccessfulRescale  4m35s  horizontal-pod-autoscaler  New size: 5; reason: All metrics below target
      Normal  SuccessfulRescale  4m5s   horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
      Normal  SuccessfulRescale  3m50s  horizontal-pod-autoscaler  New size: 1; reason: All metrics below target
    
    ```
    
    ![CleanShot 2025-03-01 at 15.06.27.png](attachment:929c3815-ab86-4719-80c5-657e254069ad:CleanShot_2025-03-01_at_15.06.27.png)
    
    ![CleanShot 2025-03-01 at 15.08.05.png](attachment:dc05f42c-ca4b-4e91-916b-a516759164c4:CleanShot_2025-03-01_at_15.08.05.png)
    
    ![https://hackjsp.tistory.com/48](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/484a5f26-a42f-4fef-9095-06be0451b89c/1.gif)
    
    https://hackjsp.tistory.com/48
    
- HPA 프로메테우스 메트릭
    
    ```bash
    kube_horizontalpodautoscaler_status_current_replicas
    **kube_horizontalpodautoscaler_status_desired_replicas**
    kube_horizontalpodautoscaler_status_target_metric
    kube_horizontalpodautoscaler_status_condition
    
    kube_horizontalpodautoscaler_spec_target_metric
    kube_horizontalpodautoscaler_spec_min_replicas
    kube_horizontalpodautoscaler_spec_max_replicas
    
    # 엔드포인트 확인
    kubectl exec -it curl -- curl -s **kube-prometheus-stack-kube-state-metrics.monitoring.svc:8080/metrics**
    kubectl exec -it curl -- curl -s kube-prometheus-stack-kube-state-metrics.monitoring.svc:8080/metrics | grep -i horizontalpodautoscaler | grep HELP
    # HELP kube_horizontalpodautoscaler_info Information about this autoscaler.
    # HELP kube_horizontalpodautoscaler_metadata_generation [STABLE] The generation observed by the HorizontalPodAutoscaler controller.
    # HELP kube_horizontalpodautoscaler_spec_max_replicas [STABLE] Upper limit for the number of pods that can be set by the autoscaler; cannot be smaller than MinReplicas.
    # HELP kube_horizontalpodautoscaler_spec_min_replicas [STABLE] Lower limit for the number of pods that can be set by the autoscaler, default 1.
    # HELP kube_horizontalpodautoscaler_spec_target_metric The metric specifications used by this autoscaler when calculating the desired replica count.
    # HELP kube_horizontalpodautoscaler_status_target_metric The current metric status used by this autoscaler when calculating the desired replica count.
    # HELP kube_horizontalpodautoscaler_status_current_replicas [STABLE] Current number of replicas of pods managed by this autoscaler.
    # HELP kube_horizontalpodautoscaler_status_desired_replicas [STABLE] Desired number of replicas of pods managed by this autoscaler.
    # HELP kube_horizontalpodautoscaler_annotations Kubernetes annotations converted to Prometheus labels.
    # HELP kube_horizontalpodautoscaler_labels [STABLE] Kubernetes labels converted to Prometheus labels.
    # HELP kube_horizontalpodautoscaler_status_condition [STABLE] The condition of this autoscaler.
    
    kubectl exec -it curl -- curl -s kube-prometheus-stack-kube-state-metrics.monitoring.svc:8080/metrics **| grep -i horizontalpodautoscaler**
    ...
    ```
    
    ![kube_horizontalpodautoscaler_status_desired_replicas](attachment:4e4b58fa-fb72-4597-a1fa-8f0f2a223bb7:CleanShot_2025-03-02_at_00.05.02.png)
    
    kube_horizontalpodautoscaler_status_desired_replicas
    
- 관련 오브젝트 삭제: **`kubectl delete deploy,svc,hpa,pod --all`**
- `도전과제` HPA : Autoscaling on **multiple** metrics and **custom metrics** - [링크](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/#autoscaling-on-multiple-metrics-and-custom-metrics) , [Blog](https://medium.com/@api.test9989/aews-5%EC%A3%BC%EC%B0%A8-eks-autoscaling-4f68154a02a8)
    
    ```bash
    apiVersion: autoscaling/v2
    kind: **HorizontalPodAutoscaler**
    metadata:
      name: php-apache
    spec:
      minReplicas: 1
      maxReplicas: 10
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: php-apache
      **metrics**:
      **- type: Resource**
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 50
      **- type: Pods**
        pods:
          metric:
            name: packets-per-second
          target:
            type: AverageValue
            averageValue: 1k
      **- type: Object**
        object:
          metric:
            name: requests-per-second
          describedObject:
            apiVersion: networking.k8s.io/v1
            kind: Ingress
            name: main-route
          target:
            type: Value
            value: 10k
    ```
    
    - 변경 api
        
        ```bash
        apiVersion: **autoscaling/v2**
        kind: HorizontalPodAutoscaler
        metadata:
          name: jekyll-hpa
        spec:
          scaleTargetRef:
            apiVersion: apps/v1
            kind: Deployment
            name: jekyll-deployment
          minReplicas: 1
          maxReplicas: 10
          **metrics:
          - type: Resource
            resource:
              name: cpu
              target:
                type: Utilization
                averageUtilization: 50**
        ```
        
    - 사용자 정의 메트릭
        
        ```bash
        type: **Object**
        object:
          metric:
            name: requests-per-second
          describedObject:
            apiVersion: networking.k8s.io/v1
            kind: Ingress
            name: main-route
          target:
            type: Value
            value: 2
        
        ---
        
        - type: **External**
          external:
            metric:
              name: queue_messages_ready
              selector:
                matchLabels:
                  queue: "worker_tasks"
            target:
              type: AverageValue
              averageValue: 30
        ```
- VPA 소개 :  pod resources.request을 최대한 **최적값**으로 수정 ⇒ ***악분님 블로그에서 기본 소개***
    - VPA는 HPA와 같이 사용할 수 없습니다.
    - VPA는 pod자원을 최적값으로 수정하기 위해 **pod를 재실행**(기존 pod를 종료하고 새로운 pod실행)합니다.
    - 계산 방식 : ‘기준값(파드가 동작하는데 필요한 최소한의 값)’ 결정 → ‘마진(약간의 적절한 버퍼)’ 추가 → 상세정리 [Link](https://devocean.sk.com/blog/techBoardDetail.do?ID=164786)
    
    ![https://malwareanalysis.tistory.com/603](attachment:51222792-43a9-4091-a13a-f0bc0ae678a7:image.png)
    
    https://malwareanalysis.tistory.com/603
    
    ![https://devocean.sk.com/blog/techBoardDetail.do?ID=164786](attachment:6010ea3b-292b-416a-a8fa-8fac3a3d60af:image.png)
    
    https://devocean.sk.com/blog/techBoardDetail.do?ID=164786
    
- 그라파나 대시보드 : 상단 cluster 는 현재 프로메테우스 메트릭 label에 없으니 무시해도됨! - [링크](https://grafana.com/grafana/dashboards/?search=vpa) 14588
    
    ![Untitled](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/399b1447-1174-4736-85b8-72b9b3b2362f/Untitled.png)
    
- 프로메테우스
    
    ```bash
    **kube_customresource_vpa_containerrecommendations_target**
    kube_customresource_vpa_containerrecommendations_target{resource="cpu"}
    kube_customresource_vpa_containerrecommendations_target{resource="memory"}
    ```
    
    ![Untitled](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/ae58714d-b860-4ba5-a812-8a08b9d50bab/Untitled.png)
    

```bash
# CRD 설치 - feat: CPU startup boost in master (#9141)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/refs/heads/master/vertical-pod-autoscaler/deploy/vpa-v1-crd-gen.yaml
# RBAC 설치 - VPA: Update vpa-rbac.yaml for allowing in place resize requests
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/refs/heads/master/vertical-pod-autoscaler/deploy/vpa-rbac.yaml

# 코드 다운로드
git clone https://github.com/kubernetes/autoscaler.git
cd ~/autoscaler/vertical-pod-autoscaler/
tree hack

# Deploy the Vertical Pod Autoscaler to your cluster with the following command.
watch -d kubectl get pod -n kube-system
cat hack/vpa-up.sh
**./hack/vpa-up.sh**

kubectl get crd | grep **autoscaling**
kubectl get **mutatingwebhookconfigurations** vpa-webhook-config
kubectl get **mutatingwebhookconfigurations** vpa-webhook-config -o json | jq
```

- 공식 예제 : pod가 실행되면 약 2~3분 뒤에 pod resource.reqeust가 VPA에 의해 수정 - [링크](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler/examples)
    - vpa에 spec.**updatePolicy**.**updateMode**를 **Off** 로 변경 시 파드에 Spec을 자동으로 변경 재실행 하지 않습니다. 기본값(Auto)

![EKS_VPA_practice-2.gif](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/1344e7d8-3170-413f-b60f-d1a23e53bf48/EKS_VPA_practice-2.gif)

```bash
# 모니터링
watch -d "kubectl top pod;echo "----------------------";kubectl describe pod | grep Requests: -A2"

# 공식 예제 배포
~~cd ~/autoscaler/vertical-pod-autoscaler/~~
cat examples/hamster.yaml
**kubectl apply -f examples/hamster.yaml && kubectl get vpa -w**

# 파드 리소스 Requestes 확인
**kubectl describe pod | grep Requests: -A2**
    Requests:
      cpu:        **100m**
      memory:     **50Mi**
--
    Requests:
      cpu:        587m
      memory:     262144k
--
    Requests:
      cpu:        **587m**
      memory:     **262144k**

# VPA에 의해 기존 파드 삭제되고 신규 파드가 생성됨
**kubectl get events --sort-by=".metadata.creationTimestamp" | grep VPA**
2m16s       Normal    EvictedByVPA             pod/hamster-5bccbb88c6-s6jkp         Pod was evicted by VPA Updater to apply resource recommendation.
76s         Normal    EvictedByVPA             pod/hamster-5bccbb88c6-jc6gq         Pod was evicted by VPA Updater to apply resource recommendation.
```

- 삭제:  `kubectl delete -f examples/hamster.yaml && cd ~/autoscaler/vertical-pod-autoscaler/ && **./hack/vpa-down.sh**`


도전과제 VPA 컨트롤러 설치 후 실습 진행 및 정리 + In-Place Pod Resource Resize (CPU) 적용 해보기



- **KEDA** with Helm **실습** : 특정 **이벤트(cron 등)**기반의 **파드** **오토 스케일링** - [Chart](https://artifacthub.io/packages/helm/kedacore/keda) , [Grafana](https://github.com/kedacore/keda/blob/main/config/grafana/keda-dashboard.json) , [Cron](https://keda.sh/docs/2.16/scalers/cron/) , [SQS_Scale](https://blog.naver.com/qwerty_1234s/223113354100) , [aws-sqs-queue](https://dev.to/vinod827/scale-your-apps-using-keda-in-kubernetes-4i3h)
    - KEDA 대시보드 JSON Import **:** https://github.com/kedacore/keda/blob/main/config/grafana/keda-dashboard.json
        
        ![스크린샷 2023-05-16 오후 3.47.15.png](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/9c4eda8c-8f21-46cb-9813-6025b2fc2b3c/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2023-05-16_%E1%84%8B%E1%85%A9%E1%84%92%E1%85%AE_3.47.15.png)
        
    
    ```bash
    # 설치 전 기존 metrics-server 제공 Metris API 확인
    kubectl get **--raw** "/apis/metrics.k8s.io" **-v=6** | jq
    **kubectl get --raw "/apis/metrics.k8s.io"** | jq
    {
      "kind": "APIGroup",
      "apiVersion": "v1",
      "name": "metrics.k8s.io",
      ...
    
    # KEDA 설치 : serviceMonitor 만으로도 충분할듯..
    cat <<EOT > keda-values.yaml
    **metricsServer**:
      useHostNetwork: true
    
    **prometheus**:
      **metricServer**:
        enabled: true
        port: **9022**
        portName: metrics
        path: /metrics
        serviceMonitor:
          # Enables ServiceMonitor creation for the Prometheus Operator
          enabled: true
      **operator**:
        enabled: true
        port: **8080**
        serviceMonitor:
          # Enables ServiceMonitor creation for the Prometheus Operator
          enabled: true
      **webhooks**:
        enabled: true
        port: **8020**
        serviceMonitor:
          # Enables ServiceMonitor creation for the Prometheus webhooks
          enabled: true
    EOT
    
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    helm install **keda** kedacore/keda --version 2.16.0 --namespace **keda** --create-namespace **-f keda-values.yaml**
    
    # KEDA 설치 확인
    **kubectl get crd | grep keda**
    kubectl get **all** -n keda
    kubectl get **validatingwebhookconfigurations** keda-admission -o yaml
    kubectl get **podmonitor,servicemonitors** -n keda
    kubectl get apiservice v1beta1.external.metrics.k8s.io -o yaml
    
    # CPU/Mem은 기존 metrics-server 의존하여, KEDA metrics-server는 외부 이벤트 소스(Scaler) 메트릭을 노출 
    ## https://keda.sh/docs/2.16/operate/metrics-server/
    kubectl get pod -n keda -l app=keda-operator-metrics-apiserver
    
    # Querying metrics exposed by KEDA Metrics Server
    **kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1"** | jq
    {
      "kind": "APIResourceList",
      "apiVersion": "v1",
      "groupVersion": "external.metrics.k8s.io/v1beta1",
      "resources": [
        {
          "name": "externalmetrics",
          "singularName": "",
          "namespaced": true,
          "kind": "ExternalMetricValueList",
          "verbs": [
            "get"
          ]
        }
      ]
    }
    
    # keda 네임스페이스에 디플로이먼트 생성
    **kubectl apply -f https://k8s.io/examples/application/php-apache.yaml -n keda
    kubectl get pod -n keda**
    
    # ScaledObject ****정책 생성 : cron
    cat <<EOT > keda-cron.yaml
    apiVersion: keda.sh/v1alpha1
    kind: **ScaledObject**
    metadata:
      name: php-apache-cron-scaled
    spec:
      minReplicaCount: 0
      maxReplicaCount: 2  # Specifies the maximum number of replicas to scale up to (defaults to 100).
      pollingInterval: 30  # Specifies how often KEDA should check for scaling events
      cooldownPeriod: 300  # Specifies the cool-down period in seconds after a scaling event
      **scaleTargetRef**:  # Identifies the Kubernetes deployment or other resource that should be scaled.
        apiVersion: apps/v1
        kind: Deployment
        name: php-apache
      **triggers**:  # Defines the specific configuration for your chosen scaler, including any required parameters or settings
      - type: **cron**
        metadata:
          timezone: Asia/Seoul
          **start**: 00,15,30,45 * * * *
          **end**: 05,20,35,50 * * * *
          **desiredReplicas**: "1"
    EOT
    **kubectl apply -f keda-cron.yaml -n keda**
    
    # 그라파나 대시보드 추가 : 대시보드 **상단**에 **namespace : keda** 로 변경하기!
    # KEDA 대시보드 Import **:** https://github.com/kedacore/keda/blob/main/config/grafana/keda-dashboard.json
    
    # 모니터링
    watch -d 'kubectl get ScaledObject,hpa,pod -n keda'
    kubectl get ScaledObject -w
    
    # 확인
    kubectl get ScaledObject,hpa,pod -n keda
    **kubectl get hpa -o jsonpath="{.items[0].spec}" -n keda | jq**
    ...
    "**metrics**": [
        {
          "**external**": {
            "metric": {
              "name": "s0-cron-Asia-Seoul-**00,15,30,45**xxxx-**05,20,35,50**xxxx",
              "selector": {
                "matchLabels": {
                  "scaledobject.keda.sh/name": "php-apache-cron-scaled"
                }
              }
            },
            "**target**": {
              "**averageValue**": "1",
              "type": "AverageValue"
            }
          },
          "type": "**External**"
        }
    
    # KEDA 및 deployment 등 삭제
    kubectl delete ScaledObject -n keda php-apache-cron-scaled && kubectl delete deploy php-apache -n keda && helm uninstall keda -n keda
    kubectl delete namespace keda
    
    ```
    
    ![https://hackjsp.tistory.com/48](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/448a680f-20a5-4a2f-b1b7-0adb62b2006b/2.gif)
    
    https://hackjsp.tistory.com/48
    
- [추천 글] if(kakaoAI)2024] 카카오페이증권의 Kubernetes 지능형 리소스 최적화 - [Blog](https://tech.kakaopay.com/post/ifkakao2024-dr-pym-project/) , [Youtube](https://www.youtube.com/watch?v=FEDSGUkUjoQ) , [PPT](https://speakerdeck.com/kakao/ifkakao24-74)
- `도전과제` KEDA 활용 : Karpenter + KEDA로 특정 시간에 AutoScaling - [링크](https://jenakim47.tistory.com/90) , [Youtube](https://youtu.be/FPlCVVrCD64) , [Airflow](https://swalloow.github.io/airflow-worker-keda-autoscaler/) , [Blog](https://dev.to/vinod827/scale-your-apps-using-keda-in-kubernetes-4i3h)
- `도전과제` KEDA HTTP Add-on 사용해보기 - [Docs](https://kedacore.github.io/http-add-on/scope.html) , [Github](https://github.com/kedacore/http-add-on)


### CPA - Cluster Proportional Autoscaler

- **소개** 및 **실습** : 노드 수 증가에 비례하여 성능 처리가 필요한 애플리케이션(컨테이너/파드)를 수평으로 자동 확장 ex. coredns - [Github](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler) [Workshop](https://www.eksworkshop.com/docs/autoscaling/workloads/cluster-proportional-autoscaler/)
    
    ![Untitled](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/564175d4-d90c-4166-8dbd-9300e6fdec21/Untitled.png)
    
    [EKS 스터디 - 5주차 2편 - CPA](https://malwareanalysis.tistory.com/604)
    
    ![4.gif](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/ba050389-f069-47ad-ba46-6a2811b48b48/4.gif)
    
    ```bash
    #
    helm repo add cluster-proportional-autoscaler https://kubernetes-sigs.github.io/cluster-proportional-autoscaler
    
    # CPA규칙을 설정하고 helm차트를 릴리즈 필요
    helm upgrade --install cluster-proportional-autoscaler cluster-proportional-autoscaler/cluster-proportional-autoscaler
    
    # nginx 디플로이먼트 배포
    cat <<EOT > cpa-nginx.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-deployment
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
          - name: nginx
            image: nginx:latest
            resources:
              limits:
                cpu: "100m"
                memory: "64Mi"
              requests:
                cpu: "100m"
                memory: "64Mi"
            ports:
            - containerPort: 80
    EOT
    kubectl apply -f cpa-nginx.yaml
    
    # CPA 규칙 설정
    cat <<EOF > cpa-values.yaml
    config:
      ladder:
        **nodesToReplicas:
          - [1, 1]
          - [2, 2]
          - [3, 3]
          - [4, 3]
          - [5, 5]**
    options:
      namespace: default
      target: "deployment/nginx-deployment"
    EOF
    kubectl describe cm cluster-proportional-autoscaler
    
    # 모니터링
    **watch -d kubectl get pod**
    
    # helm 업그레이드
    helm upgrade --install cluster-proportional-autoscaler -f cpa-values.yaml cluster-proportional-autoscaler/cluster-proportional-autoscaler
    
    # 노드 5개로 증가
    export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].AutoScalingGroupName" --output text)
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${ASG_NAME} --min-size 5 --desired-capacity 5 --max-size 5
    aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" --output table
    
    # 노드 4개로 축소
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${ASG_NAME} --min-size 4 --desired-capacity 4 --max-size 4
    aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" --output table
    ```
    
    - 삭제:  **`helm uninstall cluster-proportional-autoscaler && kubectl delete -f cpa-nginx.yaml`**
    - (참고) CPU/Memory 기반 정책 - [Blog](https://leehosu.tistory.com/entry/AEWS-5-2-Amazon-EKS-Autoscaling-CA-CPA#cpa-%EC%A0%95%EC%B1%85-%EB%B0%B0%ED%8F%AC)
        
        ```bash
         "coresToReplicas":
              [
                [ 1, 1 ],
                [ 64, 3 ],
                [ 512, 5 ],
                [ 1024, 7 ],
                [ 2048, 10 ],
                [ 4096, 15 ]
              ],
        ```
        
    
- 비교 : **Cluster Proportional Autoscaler (CPA)** vs **kubespray dns-autoscaler**  vs **EKS coreDNS autoscaler**
    
    
    | 항목 | CPA | kubespray dns-autoscaler | EKS dns autoscaler |
    | --- | --- | --- | --- |
    | 성격 | 엔진 | 템플릿 | 운영 패턴 |
    | 범용성 | ✅ 매우 높음 | ❌ CoreDNS 전용 | ⚠️ 사실상 CoreDNS |
    | 설치 | 수동 | 자동 | 수동 |
    | 관리 주체 | 사용자 | kubespray | 사용자 |
    | 커스터마이징 | ✅ 자유 | ⚠️ 제한 | ✅ 자유 |
    | 내부 구조 | 자체 | CPA 사용 | CPA 사용 |
    
    ```bash
    # https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/coredns-autoscaling.html
    
    **CoreDNS 구성 페이지
    {
      "autoScaling": {
        "enabled": true,
        "minReplicas": 2,
        "maxReplicas": 10
      }
    }**
    
    ```
    
- `도전과제` EKS addon 중 coredns 를 테라폼 배포 시, autoscaling 정책을 적용해보자

### CA/CAS - Cluster Autoscaler

- **Cluster Autoscaler(CAS) 설정** - [Workshop](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/cluster-autoscaler/) , [Helm](https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler) , [Readme](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
    - **설정 전 확인 : Auto-Discovery Setup**
        - To enable this, provide the `--node-group-auto-discovery` flag as an argument whose value is a list of tag keys that should be looked for.
        - For example, `--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled, k8s.io/cluster-autoscaler/<cluster-name>` will find the ASGs that have at least all the given tags.
        
        ```bash
        **# EKS 노드에 이미 아래 tag가 들어가 있음**
        # https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#auto-discovery-setup
        # k8s.io/cluster-autoscaler/enabled : true
        # k8s.io/cluster-autoscaler/myeks : owned
        aws ec2 describe-instances  --filters Name=tag:Name,Values=myeks-ng-1 --query "Reservations[*].Instances[*].Tags[*]" --output json | jq
        **aws ec2 describe-instances  --filters Name=tag:Name,Values=myeks-ng-1 --query "Reservations[*].Instances[*].Tags[*]" --output yaml**
        ...
        - Key: k8s.io/cluster-**autoscaler**/myeks
              Value: owned
        - Key: k8s.io/cluster-**autoscaler**/enabled
              Value: 'true'
        ...
        ```
        
        ![태그 Key 정렬해서 확인, 태그가 많을 경우 2페이지 이상에서 확인 할 것!](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/02513825-e446-425f-8801-6419ccc34652/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2023-05-17_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_11.02.25.png)
        
        태그 Key 정렬해서 확인, 태그가 많을 경우 2페이지 이상에서 확인 할 것!
        
    
    Cluster Autoscaler for AWS provides integration with Auto Scaling groups. It enables users to choose from four different options of deployment:
    
    - One Auto Scaling group
    - Multiple Auto Scaling groups
    - Auto-Discovery : Auto-Discovery is the preferred method to configure Cluster Autoscaler. Click [here](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/aws) for more information.
    - Control-plane Node setup
    
    Cluster Autoscaler will attempt to determine the **CPU**, **memory**, and **GPU** resources provided by an Auto Scaling Group based on the instance type specified in its Launch Configuration or Launch Template.
    
    ```bash
    # 현재 autoscaling(ASG) 정보 확인
    # aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='**클러스터이름**']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" --output table
    **aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" \
        --output table**
    -----------------------------------------------------------------
    |                   DescribeAutoScalingGroups                   |
    +------------------------------------------------+----+----+----+
    |  eks-ng1-44c41109-daa3-134c-df0e-0f28c823cb47  |  3 |  3 |  3 |
    +------------------------------------------------+----+----+----+
    
    # MaxSize 6개로 수정
    **export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].AutoScalingGroupName" --output text)
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${ASG_NAME} --min-size 3 --desired-capacity 3 --max-size 6**
    
    # 확인
    **aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" --output table**
    -----------------------------------------------------------------
    |                   DescribeAutoScalingGroups                   |
    +------------------------------------------------+----+----+----+
    |  eks-ng1-c2c41e26-6213-a429-9a58-02374389d5c3  |  3 |  6 |  3 |
    +------------------------------------------------+----+----+----+
    
    # 배포 : Deploy the Cluster Autoscaler (CAS)
    **curl -s -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml**
    *...
                - ./cluster-autoscaler
                - --v=4
                - --stderrthreshold=info
                - --**cloud-provider=aws**
                - --skip-nodes-with-local-storage=false # 로컬 스토리지를 가진 노드를 autoscaler가 scale down할지 결정, false(가능!)
                - --expander=least-waste # 노드를 확장할 때 어떤 노드 그룹을 선택할지를 결정, least-waste는 리소스 낭비를 최소화하는 방식으로 새로운 노드를 선택.
                - --**node-group-auto-discovery**=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/**<YOUR CLUSTER NAME>**
    ...*
    
    sed -i -e "s|<YOUR CLUSTER NAME>|**myeks**|g" cluster-autoscaler-autodiscover.yaml
    **kubectl apply -f cluster-autoscaler-autodiscover.yaml**
    
    # 확인
    kubectl get pod -n kube-system | grep cluster-autoscaler
    kubectl describe deployments.apps -n kube-system cluster-autoscaler
    **kubectl describe deployments.apps -n kube-system cluster-autoscaler | grep node-group-auto-discovery**
          --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/myeks
    
    # (옵션) cluster-autoscaler 파드가 동작하는 워커 노드가 퇴출(evict) 되지 않게 설정
    kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"
    ```

- **SCALE A CLUSTER WITH Cluster Autoscaler(CA)** - [Link](https://eksworkshop.com/docs/autoscaling/compute/cluster-autoscaler/test-ca)
    
    ![3.gif](https://prod-files-secure.s3.us-west-2.amazonaws.com/a6af158e-5b0f-4e31-9d12-0d0b2805956a/5ef148be-cf3b-4562-91fe-e838c68769d6/3.gif)
    
    ```bash
    # 모니터링 
    kubectl get nodes -w
    while true; do kubectl get node; echo "------------------------------" ; date ; sleep 1; done
    while true; do aws ec2 describe-instances --query "Reservations[*].Instances[*].{PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output text ; echo "------------------------------"; date; sleep 1; done
    
    # Deploy a Sample App
    # We will deploy an sample nginx application as a ReplicaSet of 1 Pod
    cat << EOF > nginx.yaml
    apiVersion: apps/v1
    kind: **Deployment**
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
            service: nginx
            app: nginx
        spec:
          containers:
          - image: **nginx**
            name: nginx-to-scaleout
            resources:
              **limits:
                cpu: 500m
                memory: 512Mi
              requests:
                cpu: 500m
                memory: 512Mi**
    EOF
    kubectl apply -f nginx.yaml
    kubectl get deployment/nginx-to-scaleout
    
    # Scale our ReplicaSet
    # Let’s scale out the replicaset to 15
    kubectl scale **--replicas=15** deployment/nginx-to-scaleout && date
    
    # 확인
    kubectl get pods -l app=nginx -o wide --watch
    **kubectl -n kube-system logs -f deployment/cluster-autoscaler**
    
    # 노드 자동 증가 확인
    kubectl get nodes
    aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='**myeks**']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" \
        --output table
    
    **eks-node-viewer --resources cpu,memory**
    혹은
    **eks-node-viewer**
    
    # [운영서버 EC2] 최근 1시간 Fleet API 호출 확인 - [Link](https://ap-northeast-2.console.aws.amazon.com/cloudtrailv2/home?region=ap-northeast-2#/events?EventName=CreateFleet)
    # https://ap-northeast-2.console.aws.amazon.com/cloudtrailv2/home?region=ap-northeast-2#/events?EventName=CreateFleet
    aws cloudtrail lookup-events \
      --lookup-attributes AttributeKey=EventName,AttributeValue=CreateFleet \
      --start-time "$(date -d '1 hour ago' --utc +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
    
    # (참고) Event name : UpdateAutoScalingGroup
    # https://ap-northeast-2.console.aws.amazon.com/cloudtrailv2/home?region=ap-northeast-2#/events?EventName=UpdateAutoScalingGroup
    
    # 디플로이먼트 삭제
    kubectl delete -f nginx.yaml && date
    
    # [scale-down] **노드 갯수 축소** : 기본은 10분 후 scale down 됨, 물론 아래 flag 로 시간 수정 가능 >> 그러니 **디플로이먼트 삭제 후 10분 기다리고 나서 보자!**
    # By default, cluster autoscaler will wait 10 minutes between scale down operations, 
    # you can adjust this using the --scale-down-delay-after-add, --scale-down-delay-after-delete, 
    # and --scale-down-delay-after-failure flag. 
    # E.g. --scale-down-delay-after-add=5m to decrease the scale down delay to 5 minutes after a node has been added.
    
    # 터미널1
    watch -d kubectl get node
    ```
    
    - CloudTrail 에 CreateFleet 이벤트 확인 - [Link](https://ap-northeast-2.console.aws.amazon.com/cloudtrailv2/home?region=ap-northeast-2#/events?EventName=CreateFleet)
    
    ```bash
    # CloudTrail 에 CreateFleet 이벤트 조회 : 최근 90일 가능
    aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=**CreateFleet**
    ```
    
    ![https://ap-northeast-2.console.aws.amazon.com/cloudtrailv2/home?region=ap-northeast-2#/events?EventName=CreateFleet](attachment:ae9c88c8-a63a-4353-8d94-54a6f29b1932:CleanShot_2025-03-02_at_01.20.20.png)
    
    https://ap-northeast-2.console.aws.amazon.com/cloudtrailv2/home?region=ap-northeast-2#/events?EventName=CreateFleet
    
- 리소스 **삭제**
    
    ```bash
    # 위 실습 중 디플로이먼트 삭제 후 10분 후 노드 갯수 축소되는 것을 확인 후 아래 삭제를 해보자! >> 만약 바로 아래 CA 삭제 시 워커 노드는 4개 상태가 되어서 수동으로 2대 변경 하자!
    **kubectl delete -f nginx.yaml**
    
    # size 수정 
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${ASG_NAME} --min-size 3 --desired-capacity 3 --max-size 3
    aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='myeks']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" --output table
    
    # Cluster Autoscaler 삭제
    kubectl delete -f cluster-autoscaler-autodiscover.yaml
    ```
    
- `도전과제` Cluster Over-Provisioning : 여유 노드를 미리 프로비저닝 - [Workshop](https://www.eksworkshop.com/docs/autoscaling/compute/cluster-autoscaler/overprovisioning/) , [Blog1](https://freesunny.tistory.com/57) , [Blog2](https://tommypagy.tistory.com/373) , [Blog3](https://haereeroo.tistory.com/24)
    - Spare capacity with cluster autoscaling
        
        ![CleanShot 2025-03-11 at 18.55.39.png](attachment:b65b3078-bdc3-48cc-a9fa-5a6be223a261:CleanShot_2025-03-11_at_18.55.39.png)
        
        - 노드를 수동으로 추가하는 것에 비해 노드를 **자동으로 확장하는 것의 단점** 중 하나는 때때로 자동 확장기가 너무 잘 조정되어 **여분의 용량이 없을 수 있다**는 점입니다.
        - 이는 비용을 낮추는 데 도움이 될 수 있지만, **포드를 시작하기 전에 용량을 프로비저닝해야 하므로 새 포드를 시작하는 속도가 느려집**니다.
        - 새로운 노드를 추가한 후 포드를 시작하는 것은 기존 노드에 새로운 포드를 추가하는 것보다 느립니다.
        - 노드를 프로비저닝하고 부팅해야 하는 반면, 기존 노드로 예약된 포드는 컨테이너를 당겨 부팅하기만 하면 됩니다. 컨테이너가 이미 캐시에 있는 경우 바로 부팅을 시작할 수도 있습니다.
        - 그림 6.2에 표시된 바와 같이, 새로 예약된 Pod는 부팅을 시작하기 전에 용량이 프로비저닝될 때까지 기다려야 합니다.
        - 오토스케일러를 유지하면서 이 두 가지 문제를 해결하는 한 가지 방법은 **우선순위가 낮은 플레이스홀더 포드**를 사용하는 것입니다.
        - 이 포드는 예비 용량(추가 노드를 계속 대기 상태로 유지하고 실행하는 것) 외에는 아무것도 하지 않습니다.
        - 이 Pod의 우선순위가 낮기 때문에 워크로드가 확장되면 이 Pod를 선점하고 노드 용량을 사용할 수 있습니다(그림 6.3).
        - 원문
            
            ```bash
            One of the drawbacks of autoscaling nodes compared to manually adding nodes is that sometimes the autoscaler can tune things a little too well and result in no spare capacity.
            
            This can be great for keeping costs down, but it makes it slower to start new Pods, as capacity needs to be provisioned before the Pod can start up.
            
            Adding new nodes and then starting the Pod is slower than adding new Pods to existing nodes.
            
            Nodes have to be provisioned and booted, while Pods that get scheduled onto existing nodes just have to pull the container and boot—and if the container is already in the cache, they can even start booting right away.
            
            As shown in figure 6.2, the newly scheduled Pod must wait for capacity to be provisioned before it can begin booting.
            
            One way to solve both of these problems while still keeping your autoscaler is to use a low-priority placeholder Pod.
            
            This Pod does nothing itself other than reserve capacity (keeping additional nodes up and running on standby).
            
            This Pod’s priority is low, so when your own workloads scale up, they can preempt this Pod and use the node capacity (figure 6.3).
            ```
            
        
        ![CleanShot 2025-03-11 at 18.58.31.png](attachment:14b6a4a3-88bf-49e1-bd2b-426653bd67f4:CleanShot_2025-03-11_at_18.58.31.png)
        
        - placeholder Pod deployment 를 만들려면 먼저 PriorityClass가 필요합니다.
        - 이 우선순위 클래스는 다음 목록과 같이 0보다 낮은 우선순위를 가져야 합니다(다른 모든 우선순위 클래스가 우선순위를 선점하기를 원합니다).
            
            ```bash
            apiVersion: scheduling.k8s.io/v1
            kind: **PriorityClass**
            metadata:
              name: placeholder-priority
            **value: -10**
            **preemptionPolicy: Never**
            globalDefault: false
            description: "Placeholder Pod priority."
            ```
            
        - 이제 다음 목록과 같이 **"아무것도 하지 않는" 컨테이너 배포**를 만들 수 있습니다.
            
            ```bash
            apiVersion: apps/v1
            kind: **Deployment**
            metadata:
              name: **placeholder**
            spec:
              **replicas: 10** # How many replicas do you want? This, with the CPU and memory requests, determines the size of the headroom capacity provided by the placeholder Pod.
              selector:    # 몇 개의 복제본을 원하십니까? 이는 CPU 및 메모리 요청을 통해 플레이스홀더 포드가 제공하는 헤드룸 용량의 크기를 결정합니다.
                matchLabels:
                  pod: placeholder-pod
              template:
                metadata:
                  labels:
                    pod: placeholder-pod
                spec:
                  **priorityClassName**: placeholder-priority # Uses the priority class we just created
                  **terminationGracePeriodSeconds**: 0 # We want this Pod to shut down immediately with no grace period.
                  containers: 
                  - name: ubuntu
                    image: **ubuntu**
                    command: ["sleep"]
                    args: ["infinity"]
                    resources:
                      **requests:** # The resources that will be reserved by the placeholder Pod. This should be equal to the largest Pod you wish to replace this Pod.
                        **cpu: 200m** # 플레이스홀더 포드가 예약할 리소스입니다. 이는 이 포드를 대체하려는 가장 큰 포드와 같아야 합니다.
                        **memory: 250Mi**
            
            ```
            
        - 직접 만들 때 필요한 복제본 수와 각 복제본의 크기(메모리 및 CPU 요청)를 고려하세요.
        - **크기는 가장 큰 일반 포드 크기 이상**이어야 하며, 그렇지 않으면 **플레이스홀더 포드가 선점될 때 작업량이 공간에 맞지 않을 수** 있습니다.
        - 동시에 크기를 너무 크게 늘리지 말고, 추가 용량을 예약하려면 표준 워크로드인 포드보다 훨씬 큰 복제본보다 더 많은 복제본을 사용하는 것이 좋습니다.
        - 이러한 자리 표시자 포드가 예약한 다른 포드에 의해 선점되기 위해서는 **해당 포드가 더 높은 값을 가지면서도 절대 선점 정책이 없는 우선순위 클래**스를 가져야 합니다.
        - 다행히도 기본 우선순위 클래스의 값은 0이고 선점 정책은 PrememptLowerPriority이므로 **기본적으로 다른 모든 포드가 자리 표시자 포드를 대체**합니다.
        - Kubernetes 기본값을 자체 우선순위 클래스로 나타내려면 6.11을 나열하는 것처럼 보입니다.
        - 기본값을 실제로 변경할 필요가 없으므로 설정할 필요가 없습니다.
        - 하지만 자신만의 우선순위 클래스를 만드는 경우 이 목록을 참조로 사용할 수 있습니다(실제 의도가 아니라면 globalDefault를 true로 설정하지 마세요).
        - 다시 한 번, 자리 표시자 포드 선점이 작동하려면 preemptionPolicy을 Never 로 설정하지 않도록 주의하세요.
            
            ```bash
            apiVersion: scheduling.k8s.io/v1
            kind: **PriorityClass**
            metadata:
              name: default-priority
            **value: 0** # Priority value higher than the placeholder Pods
            **preemptionPolicy: PreemptLowerPriority** # Will preempt other Pods
            **globalDefault: true** # Set as the default so other Pods will Will preempt other Pods preempt the placeholder Pods.
            description: "The global default priority. Will preempt the placeholder Pods."
            ```
            
        - 이와 같은 배포 환경에 캡슐화된 플레이스홀더 포드는 일정한 확장 공간을 제공하는 데 유용하며, 빠른 스케줄링을 위해 정해진 용량을 준비할 수 있습니다.
        - 또는 일회성 용량 프로비저닝을 위해 Job에 캡슐화하거나, 일정에 따라 용량을 프로비저닝하도록 CronJob에 캡슐화하거나, 독립형 포드로 실행할 수도 있습니다.
