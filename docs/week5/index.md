# Week 5: EKS Debugging

## Session

이번 주는 AWS에서 Container Solutions Architect로 근무하시는 정영준 님께서 진행한 세션을 바탕으로 합니다. 세션은 [EKS 디버깅 슬라이드](https://devfloor9.github.io/engineering-playbook/slides/eks-debugging/)를 따라 진행됐고, 상세 내용은 [EKS Debugging Playbook](https://devfloor9.github.io/engineering-playbook/docs/eks-best-practices/operations-reliability/eks-debugging) 페이지에 정리돼 있습니다. Week 5 문서들은 세션에서 강조된 내용과 함께 알아둘 개념을 정리하였습니다.

## Contents

- [Common Failures](1_common-failures.md) — First 5 Minutes triage, 주요 장애 패턴, 원인 층 구분
- [Node Health and AZ](2_node-health-and-az.md) — NMA, Auto Repair, Zonal Shift, Karpenter
- [Availability and Scale](3_availability-and-scale.md) — ALB 무중단 배포, Pod Identity vs IRSA, Ultra Scale
- [Observability and AIOps](4_observability-and-aiops.md) — Container Insights, 알림 설계, DevOps Agent
- [Lab](5_lab.md) — Ingress→Gateway API, CAS→Karpenter 마이그레이션 incident 사례와 재현 절차
