<!-- Global abbreviations — auto-appended to every page via pymdownx.snippets -->

*[VTEP]: VXLAN Tunnel Endpoint — VXLAN 패킷을 캡슐화/역캡슐화하는 노드
*[VXLAN]: Virtual Extensible LAN — L2 프레임을 UDP로 감싸 물리 네트워크를 넘어 전달하는 오버레이 기술
*[MTU]: Maximum Transmission Unit — 네트워크 인터페이스가 한 번에 전송할 수 있는 최대 패킷 크기
*[IRSA]: IAM Roles for Service Accounts — OIDC Federation으로 K8s ServiceAccount에 AWS IAM Role을 바인딩하는 메커니즘
*[PDB]: Pod Disruption Budget — 자발적 중단 시 최소 가용 Pod 수를 보장하는 정책
*[LBC]: AWS Load Balancer Controller — K8s Service/Ingress를 AWS NLB/ALB와 연동하는 컨트롤러
*[BGP]: Border Gateway Protocol — AS(Autonomous System) 간 경로 정보를 교환하고 정책 기반으로 라우팅을 결정하는 프로토콜
*[RFC 1918]: IANA가 사설 네트워크용으로 예약한 IPv4 주소 범위 (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
*[RFC 6598]: IANA가 CG-NAT용으로 예약한 IPv4 주소 범위 (100.64.0.0/10)
*[CG-NAT]: Carrier-Grade NAT — ISP가 공인 IP 부족을 해결하기 위해 운영하는 대규모 NAT로 100.64.0.0/10 대역을 사용하며 공인 인터넷에서 라우팅되지 않음

*[ARP]: Address Resolution Protocol — IP 주소를 MAC 주소로 매핑하여 L2 통신을 가능하게 하는 프로토콜
*[HPA]: Horizontal Pod Autoscaler — Pod 메트릭 기반으로 Deployment의 replica 수를 자동 조정하는 K8s 컨트롤러
*[VPA]: Vertical Pod Autoscaler — Pod의 resource request/limit을 실제 사용량 기반으로 최적화하는 컨트롤러
*[CAS]: Cluster Autoscaler — Pending Pod 발생 시 ASG를 통해 노드를 자동 추가/제거하는 K8s 컴포넌트
*[CPA]: Cluster Proportional Autoscaler — 노드 수에 비례하여 특정 워크로드 replica를 자동 조정하는 컨트롤러
*[KEDA]: Kubernetes Event-Driven Autoscaling — 이벤트 소스(큐, cron 등)를 기반으로 Pod를 스케일링하는 오픈소스 프로젝트
*[ASG]: Auto Scaling Group — EC2 인스턴스를 자동으로 추가/제거하는 AWS 서비스
*[KRR]: Kubernetes Resource Recommender — Prometheus 데이터 기반으로 Pod 리소스 추천값을 제공하는 CLI 도구
*[RFC 3927]: IANA가 link-local 자동 주소 설정용으로 예약한 IPv4 주소 범위 (169.254.0.0/16). 라우팅 테이블에 전파되지 않아 VPC/Pod CIDR와 충돌하지 않음
