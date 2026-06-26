variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "ec2_instance_id" {
  type = string
}

variable "rds_instance_id" {
  type = string
}

variable "enable_schedule" {
  description = "Enable/disable the auto start/stop schedule"
  type        = bool
  default     = true
}

variable "start_schedule" {
  description = "EventBridge cron expression (UTC) to start resources"
  type        = string
  default     = "cron(0 0 ? * MON-FRI *)"
}

variable "stop_schedule" {
  description = "EventBridge cron expression (UTC) to stop resources"
  type        = string
  default     = "cron(0 12 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  type    = string
  default = "Asia/Tokyo"
}
