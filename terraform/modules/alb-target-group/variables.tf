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

variable "ec2_instance_id" {
  description = "EC2 instance registered in the WebSocket target group"
  type        = string
}
