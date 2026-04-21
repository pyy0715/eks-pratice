# Week 6: GitOps on EKS with ArgoCD

Week 6은 GitOps 기반 SaaS 플랫폼 엔지니어링을 다룹니다. 스터디는 AWS SaaS GitOps 워크숍(Flux v2 기반)으로 진행되었지만, 이 문서는 ArgoCD를 주 학습 대상으로 재구성하고 Flux는 비교 관점에서만 다룹니다. GitOps 원칙과 ArgoCD 아키텍처, 확장 도구, 이벤트 드리븐 자동화 순서로 정리하며, 실습은 ArgoCD 기반 미니 SaaS 재현으로 계획되어 있습니다.

## Contents

- [GitOps Principles and Platform Engineering](1_gitops-principles.md) — 플랫폼 엔지니어링, OpenGitOps 4 원칙, SaaS tenancy 모델, EKS GitOps 도구 전체 그림
- [ArgoCD: Architecture and Patterns](2_argocd.md) — 컴포넌트, App-of-Apps, ApplicationSet, Sync model, Flux 비교, EKS Managed Capability
- [ArgoCD Ecosystem Extensions](3_argocd-extensions.md) — Argo Rollouts, Image Updater, GitOps Bridge, kro, ACK와 IaC 도구 선택 기준
- [Event-Driven Workflows for SaaS Automation](4_argo-workflows.md) — Argo Workflows와 Argo Events로 구현하는 테넌트 온보딩 자동화
- Lab (준비 중) — ArgoCD 기반 미니 SaaS 재현 시나리오
