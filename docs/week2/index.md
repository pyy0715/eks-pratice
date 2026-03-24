> Cloudnet@EKS Week2

# Week 2: EKS Networking

AWS EKS는 Amazon VPC CNI를 통해 Pod IP를 VPC 네이티브 주소로 직접 부여합니다. 오버레이 터널 없이 VPC 라우팅만으로 Pod 간 통신이 가능하며, Security Group, VPC Flow Logs, 라우팅 정책이 Pod 수준까지 그대로 적용됩니다.

Week 2에서는 VPC CNI 아키텍처부터 IP 할당 모드, Pod 용량 계산, Service/DNS, Load Balancer, Gateway API까지 EKS 네트워킹 전반을 다룹니다.

!!! info "Week 1 복습"
    aws-node DaemonSet과 kube-proxy는 Week 1에서 소개했습니다.
    자세한 내용은 [Add-ons & Capabilities](../week1/3_addons.md)와
    [Worker Node](../week1/6_worker-node.md)를 참고하세요.

---

## Contents

- [Background](0_background.md) — Overlay Network, VPC Routing, ENI, CNI, IPAM/Warm Pool 사전 개념
- [VPC CNI Architecture](1_vpc-cni.md) — CNI 바이너리·ipamd 구성, Warm Pool 할당 흐름, 환경 변수
- [IP Allocation Modes](2_ip-modes.md) — Secondary IP / Prefix Delegation / Custom Networking 비교
- [Pod Capacity](3_pod-capacity.md) — maxPods 공식, Managed Node Group 결정 우선순위
- [Pod Networking](4_pod-networking.md) — veth pair, Policy Routing, SNAT 흐름
- [Service & DNS](5_service-dns.md) — kube-proxy 모드(iptables/nftables/eBPF), CoreDNS 최적화
- [Load Balancer Controller](6_load-balancer.md) — AWS LBC 설치, NLB IP 모드, ALB Ingress
- [Gateway API & ExternalDNS](7_gateway-dns.md) — Gateway API 리소스 구조, Route 53 자동 연동
- [Lab](8_lab.md) — 실습 체크리스트 및 디버깅 명령어
