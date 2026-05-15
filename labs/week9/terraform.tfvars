ClusterBaseName   = "genai-eks"
KubernetesVersion = "1.34"
TargetRegion      = "us-east-2"

VpcBlock              = "10.0.0.0/16"
availability_zones    = ["us-east-2a", "us-east-2b", "us-east-2c"]
public_subnet_blocks  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_blocks = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

gpu_instance_families    = ["g6e", "g6", "g5"]
neuron_instance_families = ["inf2", "trn1"]

gpu_capacity_type    = ["on-demand"]
neuron_capacity_type = ["on-demand"]
