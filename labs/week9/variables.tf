variable "ClusterBaseName" {
  description = "EKS cluster name"
  type        = string
  default     = "genai-eks"
}

variable "KubernetesVersion" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "TargetRegion" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "VpcBlock" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "public_subnet_blocks" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_blocks" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "gpu_instance_families" {
  description = "GPU instance families for Karpenter NodePool"
  type        = list(string)
  default     = ["g6e", "g6", "g5"]
}

variable "neuron_instance_families" {
  description = "Neuron instance families for Karpenter NodePool"
  type        = list(string)
  default     = ["inf2", "trn1"]
}

variable "gpu_capacity_type" {
  description = "Capacity type for GPU NodePool"
  type        = list(string)
  default     = ["on-demand"]
}

variable "neuron_capacity_type" {
  description = "Capacity type for Neuron NodePool"
  type        = list(string)
  default     = ["on-demand"]
}
