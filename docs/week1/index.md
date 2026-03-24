# Week 1: EKS Introduction & Deploy

EKS 아키텍처 개요부터 클러스터 구성 요소, 인증 체계, 엔드포인트 접근 제어, 워커 노드 내부 구조까지 다룹니다.

## Contents

- [Architecture](1_architecture.md) — EKS 아키텍처 개요 (컨트롤 플레인 / 데이터 플레인 VPC 구조)
- [Data Plane](2_data-plane.md) — 데이터 플레인 컴퓨팅 옵션 (Managed Node Groups, Auto Mode, Fargate, Hybrid Nodes)
- [Add-ons & Capabilities](3_addons.md) — EKS 관리형 Add-on 및 Capabilities (ACK, Argo CD, kro)
- [Authentication](4_authentication.md) — IAM 인증 및 Kubernetes 인가 (kubeconfig, Access Entries)
- [Endpoint Access](5_endpoint-access.md) — API Server 엔드포인트 접근 제어 (Public / Public+Private / Private Only)
- [Worker Node](6_worker-node.md) — 워커 노드 내부 구조 (containerd, kubelet, VPC CNI)
- [Lab](7_lab.md) — EKS 클러스터 구성 실습
