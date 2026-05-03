# Week 7: EKS Cluster Upgrades

## Session

이번 주는 [Amazon EKS Upgrades Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/693bdee4-bc31-41d5-841f-54e3e54f8f4a)을 기반으로 EKS 클러스터 업그레이드 전략과 실습을 정리합니다. 워크샵은 v1.30 클러스터에서 시작하여 In-place(→v1.31)와 Blue/Green(→v1.32) 두 가지 전략을 모두 다룹니다. Terraform과 ArgoCD 기반 GitOps를 활용하며, Managed Node Group, Karpenter, Self-managed, Fargate 네 가지 data plane 유형 모두의 업그레이드를 실습합니다.

## Contents

- [Version Lifecycle](1_version-lifecycle.md) — K8s 릴리스 주기, EKS 지원 타임라인, Version Policy, Shared Responsibility
- [Upgrade Preparation](2_upgrade-preparation.md) — 사전 요구사항, Upgrade Insights, API deprecation 도구, add-on 호환성
- [Upgrade Strategies](3_upgrade-strategies.md) — In-Place vs Blue/Green 비교, Version Skew 전략, PDB, 전략 선택 기준
- [In-Place Upgrade](4_in-place-upgrade.md) — Control Plane, Add-on, MNG, Karpenter, Self-managed, Fargate 업그레이드
- [Blue/Green Upgrade](5_blue-green-upgrade.md) — Green 클러스터 생성, Stateless/Stateful Migration, Traffic Routing
