variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "listener_arn" {
  description = "ALB listener ARN to attach the /ws/chat* rule to (module.alb.http_listener_arn)"
  type        = string
}
