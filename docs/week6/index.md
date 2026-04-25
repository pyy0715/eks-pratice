# Week 6: GitOps on EKS with ArgoCD

Week 6은 GitOps 기반 SaaS 플랫폼 엔지니어링을 다룹니다. 스터디는 AWS SaaS GitOps 워크숍(Flux v2 기반)으로 진행되었지만, 이 문서는 Argo CD를 주 학습 대상으로 재구성하고 Flux는 비교 관점에서만 다룹니다. GitOps 원칙, Argo CD 아키텍처, Argo 생태계(Rollouts, Workflows, Events, Image Updater), AWS 리소스 통합 패턴(GitOps Bridge, kro, ACK) 순서로 정리하며, 실습은 Argo CD 기반 미니 SaaS 재현으로 계획되어 있습니다.

## Contents

- [GitOps Principles and Platform Engineering](1_gitops-principles.md) — 플랫폼 엔지니어링, OpenGitOps 4 원칙, SaaS tenancy 모델, EKS GitOps 도구 전체 그림
- [ArgoCD: Architecture and Patterns](2_argocd.md) — 컴포넌트, App-of-Apps, ApplicationSet, Sync model, Flux 비교, EKS Managed Capability
- [Argo Ecosystem](3_argo-ecosystem.md) — Argo CD Image Updater, Argo Rollouts, Argo Workflows, Argo Events와 테넌트 온보딩 자동화 사례
- [AWS Integration Patterns](4_aws-integration.md) — GitOps Bridge, kro, ACK로 AWS 리소스를 Git에서 관리하는 패턴과 IaC 도구 선택 기준
- [Lab](5_lab.md) — GitOps Bridge 부트스트랩, App-of-Apps, ApplicationSet staggered 3-tier 배포, SQS 온보딩, Image Updater, Rollouts ALB canary
