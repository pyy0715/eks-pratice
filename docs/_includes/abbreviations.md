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
*[CR]: Custom Resource — CustomResourceDefinition(CRD)으로 정의된 사용자 정의 리소스. Application, ApplicationSet처럼 K8s API로 다룰 수 있는 객체

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

<!-- GPU / ML -->
*[ASIC]: Application-Specific Integrated Circuit — 특정 용도에 최적화된 전용 반도체 칩. Trainium/Inferentia가 ML 연산 전용 ASIC
*[GFD]: GPU Feature Discovery — NVIDIA Device Plugin과 함께 배포되어 GPU 모델, 드라이버 버전, 메모리 등의 라벨을 노드에 자동 추가하는 컴포넌트
*[NEFF]: Neuron Executable File Format — AWS Neuron Compiler가 출력하는 컴파일된 모델 바이너리. Neuron Runtime이 Trainium/Inferentia에서 실행
*[DRA]: Dynamic Resource Allocation — Kubernetes 1.31+ 에서 도입된 차세대 디바이스 할당 프레임워크. 속성 기반 GPU 선택과 공유를 지원
*[MIG]: Multi-Instance GPU — NVIDIA A100/H100에서 하나의 물리 GPU를 최대 7개의 독립 인스턴스로 분할하는 기술
*[TP]: Tensor Parallelism — 하나의 레이어를 여러 GPU에 분할하여 동시 계산하는 병렬화 기법. AllReduce 통신이 필요하므로 NVLink 급 대역폭 필수
*[PP]: Pipeline Parallelism — 모델을 레이어 단위로 순차 분할하여 GPU별로 다른 레이어를 처리하는 병렬화 기법. 통신량이 TP보다 적어 PCIe에서도 동작
*[SOCI]: Seekable OCI — 컨테이너 이미지를 전체 다운로드 없이 필요한 레이어만 lazy loading하는 기술

*[ANN]: Approximate Nearest Neighbor — 고차원 벡터 공간에서 정확한 최근접 대신 근사치를 빠르게 찾는 검색 알고리즘
*[HNSW]: Hierarchical Navigable Small World — 계층적 그래프 구조로 고차원 벡터의 근사 최근접 이웃을 빠르게 탐색하는 인덱싱 알고리즘
*[TEI]: Text Embeddings Inference — Hugging Face가 제공하는 Rust 기반 임베딩 모델 서빙 엔진. 토큰 기반 동적 배칭 지원

*[EFA]: Elastic Fabric Adapter — OS bypass로 커널을 건너뛰고 네트워크 디바이스와 직접 통신하는 고성능 네트워크 인터페이스. Multi-node 분산 학습에서 노드 간 통신 병목을 해결
*[NCCL]: NVIDIA Collective Communications Library — GPU 간 AllReduce, Broadcast 등 collective 통신을 최적화하는 라이브러리. EFA와 함께 multi-node 학습에 사용
*[DLC]: Deep Learning Container — AWS가 관리하는 pre-built ML 컨테이너 이미지. CUDA, cuDNN, NCCL 등 GPU 라이브러리가 포함된 상태로 ECR에서 제공

<!-- Auth RFCs -->
*[RFC 6749]: The OAuth 2.0 Authorization Framework — 사용자가 비밀번호를 넘기지 않고 서드파티 애플리케이션에 리소스 접근 권한을 위임하도록 표준화한 프로토콜
*[RFC 6750]: OAuth 2.0 Bearer Token Usage — HTTP Authorization 헤더에 토큰을 실어 보내는 방식을 정의한 표준
*[RFC 7519]: JSON Web Token (JWT) — 서명된 JSON 토큰 형식 표준
