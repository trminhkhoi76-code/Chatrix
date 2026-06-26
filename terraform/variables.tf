variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name (used for tagging and naming resources)"
  type        = string
  default     = "chatrix"
}