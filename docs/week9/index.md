# Week 9: GenAI on EKS

## Session

이번 주는 두 개의 AWS 워크샵을 기반으로 EKS Auto Mode 클러스터에서 GenAI 플랫폼을 구축하는 과정을 정리합니다. [GenAI on EKS 워크샵](https://catalog.workshops.aws/genai-on-eks/ko-KR)에서는 GPU 기반 vLLM 서빙과 Prometheus/Grafana 모니터링을, [K8s Agentic Platform 워크샵](https://catalog.workshops.aws/k8sagenticplatform/ko-KR)에서는 Neuron 기반 서빙, AI Gateway(LiteLLM), Observability(Langfuse), Agentic AI 애플리케이션을 다룹니다.

## Contents

- [Background](0_background.md) — AWS accelerator 및 instance 선택, AI/ML 도구 생태계, ML 컨테이너 이미지(DLC/NGC), Container OS(Bottlerocket)
- [GPU on Kubernetes](1_gpu-on-kubernetes.md) — Device Plugin Framework, GPU scheduling 규칙, EKS GPU 관리, Multi-GPU parallelism
- [GenAI Platform Components](2_genai-components.md) — AI Gateway(LiteLLM), LLM Serving(vLLM), Observability(Langfuse), RAG Pipeline, Agentic AI(Strands)
- [Workshop - GenAI on EKS](3_genai-on-eks.md) — 레포 구조, Terraform bootstrapping, NodePool 구성, 모니터링 스택, vLLM 배포 및 추론 아키텍처
- [Workshop - K8s Agentic Platform](4_k8s-agentic-platform.md) — Starter Kit 구조, Neuron 서빙, LiteLLM AI Gateway, Langfuse Observability, Loan Buddy Agent(LangGraph + MCP)
