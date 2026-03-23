# Lab: EKS Cluster Setup

## Lab Code

[`labs/week1/`](https://github.com/pyy0715/eks-pratice/tree/main/labs/week1)

## Getting Started

```bash
cd labs/week1
terraform init
```

### Select Endpoint Access Mode

**Public Endpoint만 활성화** — kubectl을 어디서든 사용 가능, API 서버가 인터넷에 노출됨

```bash
terraform apply -var-file=public.tfvars
```

**Public + Private Endpoint 모두 활성화** — kubectl은 공인 IP 제한, 노드↔API 서버 트래픽은 VPC 내부로

```bash
terraform apply -var-file=public_and_private.tfvars
```

When using `public_and_private.tfvars`, two things change compared to public-only mode:

- **API server public access** is restricted to your current IP (`ssh_access_cidr`). kubectl from other networks will be blocked.
- **Node-to-API-server traffic** stays within the VPC via the managed ENI. No internet round-trip for control plane communication.

### Cleanup

```bash
terraform destroy -var-file=public.tfvars
# 또는
terraform destroy -var-file=public_and_private.tfvars
```

