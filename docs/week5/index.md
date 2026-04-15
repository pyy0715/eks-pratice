# Week 5: EKS Debugging and Operations

Week 1-4가 EKS가 평상시 어떻게 동작하는지를 다뤘다면, Week 5는 그 구조가 고장났을 때 무엇을 어떤 순서로 확인하는지에 집중합니다. 단일 커리큘럼이 아니라 AWS SA가 진행한 디버깅 세션을 기반으로, 공식 문서, AWS 블로그, 실제 운영 사례를 함께 엮어 장애 대응 관점의 EKS 운영 지식을 정리합니다.

## Contents

- [Debugging Methodology](1_debugging-methodology.md) — 7계층 관점으로 장애 지점을 좁히는 법, First 5 Minutes triage, 핵심 도구 세트
- [Common Failures](2_common-failures.md) — CrashLoopBackOff, OOMKilled, FailedMount, Node NotReady 등 자주 만나는 패턴과 근본 원인
- [Node Health and AZ Failures](3_node-health-and-az.md) — Node Monitoring Agent, ARC Zonal Shift, Karpenter 장애 모드
- [Availability and Scale](4_availability-and-scale.md) — ALB 무중단 스케일, Pod lifecycle, Ultra-scale clusters
- [Observability and AIOps](5_observability-and-aiops.md) — Container Insights, 비용 최적화, 알림 설계, Detection as Code

## Session Background

이번 주는 AWS 솔루션즈 아키텍트가 devfloor9 engineering-playbook의 [EKS Debugging](https://devfloor9.github.io/engineering-playbook/docs/eks-best-practices/operations-reliability/eks-debugging) 페이지를 중심으로 진행한 세션이 바탕입니다. 세션에서 언급된 AWS 공식 가이드, 블로그, 현업 운영 사례는 각 소문서의 본문과 각주에서 맥락과 함께 인용합니다.
