# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as prefix for all resources"
  type        = string
  default     = "chatrix"
}

variable "environment" {
  description = "Deployment environment (prod / staging / dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Must be one of: prod, staging, dev."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ---------------------------------------------------------------------------
# EC2
# ---------------------------------------------------------------------------

variable "ec2_instance_type" {
  description = "EC2 instance type. Use t4g.* (ARM) for best price/performance"
  type        = string
  default     = "t4g.small" # 2 vCPU / 2 GB — runs both Java services comfortably
}

variable "ec2_key_name" {
  description = "Name of an existing EC2 Key Pair for SSH access. Leave empty to use SSM Session Manager only (recommended)"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into EC2. Only used when ec2_key_name is set"
  type        = string
  default     = "0.0.0.0/0" # Restrict to your IP in production
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro" # Smallest available for MySQL
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "chatrix"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "chatrix"
}

variable "db_password" {
  description = "Database master password (stored in SSM SecureString)"
  type        = string
  sensitive   = true
}

variable "db_allocated_storage_gb" {
  description = "Initial RDS storage in GB"
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# ElastiCache (Redis)
# ---------------------------------------------------------------------------

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_auth_token" {
  description = "Redis AUTH token (16–128 chars). Must match spring.data.redis.password in app config"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redis_auth_token) >= 16 && length(var.redis_auth_token) <= 128
    error_message = "Redis auth token must be between 16 and 128 characters."
  }
}

# ---------------------------------------------------------------------------
# Application secrets
# ---------------------------------------------------------------------------

variable "jwt_secret" {
  description = "HMAC-SHA JWT signing secret (≥32 chars). Must be identical on both chatrix-api and chatrix-websocket"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jwt_secret) >= 32
    error_message = "JWT secret must be at least 32 characters."
  }
}

# ---------------------------------------------------------------------------
# ALB / TLS
# ---------------------------------------------------------------------------

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Leave empty to serve plain HTTP (not recommended for production)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Your domain (e.g. chatrix.example.com). Used only for documentation in outputs"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------

variable "uploads_lifecycle_days" {
  description = "Days after which uploaded files are automatically deleted (set 0 to disable)"
  type        = number
  default     = 365
}

# ---------------------------------------------------------------------------
# Application ports
# ---------------------------------------------------------------------------

variable "app_api_port" {
  description = "Port the chatrix-api REST service listens on"
  type        = number
  default     = 8080
}

variable "app_ws_port" {
  description = "Port the chatrix-websocket Netty service listens on"
  type        = number
  default     = 8081
}

# ---------------------------------------------------------------------------
# Database engine
# ---------------------------------------------------------------------------

variable "db_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "db_parameter_group_family" {
  description = "RDS parameter group family (must match db_engine_version)"
  type        = string
  default     = "mysql8.0"
}

variable "db_port" {
  description = "MySQL port"
  type        = number
  default     = 3306
}

# ---------------------------------------------------------------------------
# Redis engine
# ---------------------------------------------------------------------------

variable "redis_engine_version" {
  description = "ElastiCache Redis engine version"
  type        = string
  default     = "7.1"
}

variable "redis_parameter_group_family" {
  description = "ElastiCache parameter group family (must match redis_engine_version major)"
  type        = string
  default     = "redis7"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

# ---------------------------------------------------------------------------
# Schedule (cost-saving start/stop)
# ---------------------------------------------------------------------------

variable "enable_schedule" {
  description = "Enable EventBridge automatic start/stop schedule. Set false to disable without deleting resources"
  type        = bool
  default     = true
}

variable "schedule_stop_cron" {
  description = <<-EOT
    Cron expression (Asia/Tokyo) for automatic STOP.
    Default: Mon–Fri 20:00 JST.
    Format:  cron(Minutes Hours DayOfMonth Month DayOfWeek Year)
    Examples:
      Mon-Fri 20:00 JST  →  cron(0 20 ? * MON-FRI *)
      Every day 22:00    →  cron(0 22 ? * * *)
  EOT
  type    = string
  default = "cron(0 20 ? * MON-FRI *)"
}

variable "schedule_start_cron" {
  description = <<-EOT
    Cron expression (Asia/Tokyo) for automatic START.
    Default: Mon–Fri 08:00 JST.
  EOT
  type    = string
  default = "cron(0 8 ? * MON-FRI *)"
}

variable "enable_redis_stop" {
  description = <<-EOT
    When true, Redis is DELETED on stop and RECREATED on start.
    Saves ~$14/month during off-hours, but start takes ~5 extra minutes.
    Set false to leave Redis always running (safer for production).
  EOT
  type    = bool
  default = false
}
