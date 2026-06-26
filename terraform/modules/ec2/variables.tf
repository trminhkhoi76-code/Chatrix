variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_id" {
  description = "Public subnet ID where the EC2 instance is placed"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

variable "ami_id" {
  description = "Amazon Linux 2023 ARM64 AMI ID"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name (optional)"
  type        = string
  default     = null
}

variable "alb_security_group_id" {
  type = string
}

variable "rds_security_group_id" {
  type = string
}

variable "valkey_security_group_id" {
  type = string
}

variable "s3_artifact_bucket" {
  type = string
}

variable "ssm_parameter_prefix" {
  description = "SSM path prefix (e.g. /chatrix)"
  type        = string
  default     = "/chatrix"
}
