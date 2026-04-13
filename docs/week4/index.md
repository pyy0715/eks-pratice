# Week 4: EKS Identity and Access Management

EKS의 인증/인가는 AWS IAM과 Kubernetes RBAC을 EKS Authorizer로 연결하는 구조입니다. 이 주에는 운영자가 kubectl로 클러스터를 호출하는 경로와 Pod이 AWS API를 호출하는 경로를 단계별로 따라가며 각 단계에서 어떤 컴포넌트가 무엇을 검증하는지를 정리합니다.

## Contents

- [Background](0_background.md) — Bearer 토큰, JWT, OAuth 2.0 / OpenID Connect, Kubernetes Webhook 확장 모델, AWS SigV4 선수 지식
- [Operator Authentication and Authorization](2_operator-auth.md) — kubectl 토큰의 실체와 EKS Authorizer
- [Kubernetes RBAC](3_rbac.md) — Pod이 Kubernetes API를 호출할 때의 권한 모델
- [Pod Workload Identity](4_pod-workload-identity.md) — Pod이 AWS API를 호출할 때 사용하는 IRSA와 EKS Pod Identity
- [Lab](5_lab.md) — Token/Access Entry, RBAC, IRSA, Pod Identity 실습과 비교
