variable "ClusterBaseName" {
  description = "Base name of the cluster."
  type        = string
  default     = "week6-argocd"
}

variable "KubernetesVersion" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.35"
}

variable "WorkerNodeInstanceType" {
  description = "EC2 instance type for the worker nodes."
  type        = string
  default     = "t3.large"
}

variable "WorkerNodeCount" {
  description = "Number of worker nodes."
  type        = number
  default     = 3
}

variable "WorkerNodeVolumesize" {
  description = "Volume size for worker nodes (in GiB)."
  type        = number
  default     = 30
}

variable "TargetRegion" {
  description = "AWS region where the resources will be created."
  type        = string
  default     = "ap-northeast-2"
}

variable "availability_zones" {
  description = "List of availability zones."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

variable "VpcBlock" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "192.168.0.0/16"
}

variable "private_subnet_blocks" {
  description = "List of CIDR blocks for the private subnets."
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24"]
}

variable "public_subnet_blocks" {
  description = "List of CIDR blocks for the public subnets."
  type        = list(string)
  default     = ["192.168.101.0/24", "192.168.102.0/24", "192.168.103.0/24"]
}

variable "MyDomain" {
  description = "Public domain name for Ingress resources (used by ArgoCD UI and Rollouts sample)."
  type        = string
}

variable "GitOpsRepoURL" {
  description = "HTTPS URL of the Git repository that ArgoCD tracks (root App-of-Apps and tenant values live here)."
  type        = string
}

variable "GitOpsRepoRevision" {
  description = "Branch or tag that ArgoCD tracks."
  type        = string
  default     = "main"
}

variable "ArgoCDChartVersion" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "9.5.4"
}
