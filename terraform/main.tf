terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket         = "chatrix-terraform-state"
    key            = "chatrix/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Stage     = var.environment
      ManagedBy = "terraform"
    }
  }
}

# Standalone test resource used to exercise the terraform-plan/apply CI pipeline
# and the IAM auto-attach-missing-policy workflow (sqs is intentionally not yet
# covered by .github/iam/terraform-deploy-policy.json).
resource "aws_sqs_queue" "notifications" {
  name                      = "${var.project_name}-${var.environment}-notifications"
  message_retention_seconds = 86400

  tags = {
    Name = "${var.project_name}-${var.environment}-notifications"
  }
}
