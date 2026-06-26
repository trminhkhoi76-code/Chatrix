variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_url" {
  description = "Full JDBC URL for MySQL"
  type        = string
}

variable "db_username" {
  type    = string
  default = "chatrix"
}

variable "db_password" {
  type    = string
  default = "supersecretpassword"
}

variable "jwt_secret" {
  type    = string
  default = "supersecretjwtkeythatshouldbe32charsormore"
}

variable "redis_host" {
  type = string
}

variable "redis_port" {
  type    = string
  default = "6379"
}

variable "storage_base_url" {
  type = string
}

variable "storage_upload_dir" {
  type    = string
  default = "/opt/chatrix/uploads"
}
