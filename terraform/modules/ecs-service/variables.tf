variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "service_name" {
  description = "Short service identifier used in resource names (e.g. api, websocket)"
  type        = string
}

variable "cluster_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnets — assign_public_ip avoids NAT Gateway cost"
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "image_uri" {
  description = "Full ECR image URI including tag (e.g. 123456.dkr.ecr.ap-northeast-1.amazonaws.com/chatrix-dev-api:latest)"
  type        = string
}

variable "container_port" {
  type = number
}

variable "task_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU)"
  type        = number
}

variable "task_memory" {
  description = "Fargate memory in MB"
  type        = number
}

variable "desired_count" {
  description = "Number of running tasks"
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Environment variables injected into the container"
  type        = map(string)
  default     = {}
}
