variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "chatrix"
}

variable "db_username" {
  type    = string
  default = "chatrix"
}

variable "db_password" {
  type    = string
  default = "supersecretpassword"
}

variable "engine_version" {
  type    = string
  default = "8.0"
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect to RDS (EC2 SG)"
  type        = string
}
