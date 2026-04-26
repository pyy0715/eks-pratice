########################
# SQS — tenant onboarding queue (Scenario 2)
########################

resource "aws_sqs_queue" "tenant_onboarding" {
  name                       = "${var.ClusterBaseName}-tenant-onboarding"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  tags = {
    Environment = "cloudneta-lab"
    Week        = "6"
    Purpose     = "argo-events-tenant-onboarding"
  }
}

########################
# ECR — sample app registry (Scenario 3)
########################

resource "aws_ecr_repository" "sample_app" {
  name                 = "${var.ClusterBaseName}/sample-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "cloudneta-lab"
    Week        = "6"
  }
}
