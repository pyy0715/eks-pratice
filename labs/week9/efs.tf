resource "aws_efs_file_system" "this" {
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name        = "${var.ClusterBaseName}-efs"
    Environment = "cloudneta-lab"
    Week        = "week9"
    Terraform   = "true"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.ClusterBaseName}-efs-sg"
  description = "Allow NFS from VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.VpcBlock]
  }

  tags = {
    Name = "${var.ClusterBaseName}-efs-sg"
  }
}

resource "aws_efs_mount_target" "this" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}
