<!-- Global abbreviations — auto-appended to every page via pymdownx.snippets -->

<!-- Networking -->
*[ARP]: Address Resolution Protocol — IP 주소를 MAC 주소로 매핑해 L2 통신을 가능하게 하는 프로토콜
*[BGP]: Border Gateway Protocol — AS(Autonomous System) 간 경로 정보를 교환하고 정책 기반으로 라우팅을 결정하는 프로토콜
*[VXLAN]: Virtual Extensible LAN — L2 프레임을 UDP로 감싸 물리 네트워크를 넘어 전달하는 오버레이 기술
*[VTEP]: VXLAN Tunnel Endpoint — VXLAN 패킷을 캡슐화/역캡슐화하는 노드
*[MTU]: Maximum Transmission Unit — 네트워크 인터페이스가 한 번에 전송할 수 있는 최대 패킷 크기
*[CG-NAT]: Carrier-Grade NAT — ISP가 공인 IP 부족을 해결하기 위해 운영하는 대규모 NAT. 100.64.0.0/10 대역을 사용하며 공인 인터넷에서 라우팅되지 않음

<!-- IP address ranges (RFCs) -->
*[RFC 1918]: 사설 네트워크용으로 IANA가 예약한 IPv4 주소 범위 (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
*[RFC 3927]: link-local 자동 주소 설정용으로 IANA가 예약한 IPv4 주소 범위 (169.254.0.0/16). 라우팅 테이블에 전파되지 않아 VPC/Pod CIDR와 충돌하지 않음
*[RFC 6598]: CG-NAT용으로 IANA가 예약한 IPv4 주소 범위 (100.64.0.0/10)

<!-- Kubernetes primitives -->
*[SA]: ServiceAccount — 클러스터 내 워크로드의 K8s 신원
*[PDB]: Pod Disruption Budget — 자발적 중단 시 최소 가용 Pod 수를 보장하는 정책
*[SAR]: SubjectAccessReview — 특정 주체가 특정 action을 수행할 수 있는지 K8s API 서버에 질의하는 리소스
*[TR]: TokenReview — 특정 토큰이 유효한지 K8s API 서버에 질의하는 리소스

<!-- Autoscaling -->
*[CAS]: Cluster Autoscaler — Pending Pod 발생 시 ASG를 통해 노드를 자동 추가/제거하는 K8s 컴포넌트
*[CPA]: Cluster Proportional Autoscaler — 노드 수에 비례해 특정 워크로드 replica를 자동 조정하는 컨트롤러
*[KEDA]: Kubernetes Event-Driven Autoscaling — 이벤트 소스(큐, cron 등)를 기반으로 Pod을 스케일링하는 오픈소스 프로젝트
*[KRR]: Kubernetes Resource Recommender — Prometheus 데이터 기반으로 Pod 리소스 추천값을 제공하는 CLI 도구

<!-- AWS services & integrations -->
*[LBC]: AWS Load Balancer Controller — K8s Service/Ingress를 AWS NLB/ALB와 연동하는 컨트롤러
*[IMDS]: Instance Metadata Service — EC2 인스턴스 내부에서 자격 증명과 메타데이터를 제공하는 169.254.169.254 서비스
*[NMA]: Node Monitoring Agent — EKS 노드에 DaemonSet으로 설치되어 kubelet, containerd, CNI, dmesg 로그와 상태를 감시하고 NodeCondition으로 이상을 노출하는 add-on

<!-- Auth protocols & tokens -->
*[JWKS]: JSON Web Key Set — JWT 서명 검증용 공개키 집합. 보통 OIDC Provider의 `/keys` 경로에 노출

<!-- Signing algorithms -->
*[SigV4]: AWS Signature Version 4 — AWS API 요청에 HMAC-SHA256 기반 서명을 부여하는 프로토콜
*[RS256]: RSA Signature with SHA-256 — RSA 개인키로 SHA-256 해시에 서명하는 비대칭 서명 알고리즘. OIDC Core가 필수 지원 알고리즘으로 지정

<!-- Auth RFCs -->
*[RFC 6749]: The OAuth 2.0 Authorization Framework — 사용자가 비밀번호를 넘기지 않고 서드파티 애플리케이션에 리소스 접근 권한을 위임하도록 표준화한 프로토콜
*[RFC 6750]: OAuth 2.0 Bearer Token Usage — HTTP Authorization 헤더에 토큰을 실어 보내는 방식을 정의한 표준
*[RFC 7519]: JSON Web Token (JWT) — 서명된 JSON 토큰 형식 표준
