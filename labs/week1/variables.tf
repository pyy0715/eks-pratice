variable "KeyName" {
  description = "Name of an existing EC2 KeyPair to enable SSH access to the instances."
  type        = string
}

variable "ssh_access_cidr" {
  description = "Allowed CIDR for SSH access."
  type        = string
}

variable "endpoint_public_access" {
  description = "Whether to enable public access to the EKS API server endpoint."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Whether to enable private access to the EKS API server endpoint."
  type        = bool
  default     = false
}

variable "ClusterBaseName" {
  description = "Base name of the cluster."
  type        = string
  default     = "myeks"
}

variable "KubernetesVersion" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.34"
}

variable "WorkerNodeInstanceType" {
  description = "EC2 instance type for the worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "WorkerNodeCount" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
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

variable "public_subnet_blocks" {
  description = "List of CIDR blocks for the public subnets."
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24"]
}
