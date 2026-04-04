# Week 3: EKS Autoscaling

EKS 클러스터에서 워크로드 변화에 대응하는 스케일링 전략을 다룹니다. Pod 수준(HPA, VPA)부터 Node 수준(CAS, Karpenter), 서버리스(Fargate)까지 각 방식의 동작 원리와 트레이드오프를 비교합니다.

## Contents

- [Overview](1_overview.md) — 스케일링 기술 계층, 전략 의사결정 프레임워크, AWS/K8s 정책 비교
- [Pod Autoscaling](2_pod-autoscaling.md) — Horizontal/Vertical Pod Autoscaler 동작, 메트릭, 주의사항
- [Node Autoscaling](3_node-autoscaling.md) — CPA, Cluster Autoscaler, Karpenter 비교 및 동작
- [Fargate](4_fargate.md) — Firecracker microVM 기반 서버리스 컴퓨팅, 제약사항, 로깅
- [Lab](5_lab.md) — 실습 환경 배포 및 스케일링 실습 체크리스트
