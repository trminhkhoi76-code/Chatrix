terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use S3 backend for team collaboration:
  # backend "s3" {
  #   bucket         = "chatrix-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "chatrix-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-${local.ec2_arch}"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  project = var.project
  env     = var.environment
  name_prefix = "${var.project}-${var.environment}"

  # Automatically pick ARM or x86 AMI based on instance type family
  arm_families = ["t4g", "m7g", "m6g", "c7g", "c6g", "r7g", "r6g"]
  instance_family = split(".", var.ec2_instance_type)[0]
  ec2_arch = contains(local.arm_families, local.instance_family) ? "arm64" : "x86_64"
}
