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
  description = "Private subnet IDs for the cache subnet group"
  type        = list(string)
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "num_cache_clusters" {
  description = "Number of nodes in the cluster (1 = primary only; >1 enables automatic failover)"
  type        = number
  default     = 1
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to Valkey on port 6379 (e.g. ECS task SGs)"
  type        = list(string)
}