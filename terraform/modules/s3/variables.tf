variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "account_id" {
  description = "AWS account ID — appended to bucket name for global uniqueness"
  type        = string
}
