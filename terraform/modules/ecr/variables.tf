variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "services" {
  description = "List of service names — one ECR repo is created per entry"
  type        = list(string)
}
