# ECR Repository Module Variables

variable "repository_name" {
  description = "Name of the ECR repository to create"
  type        = string
}


# Repository Configuration
variable "image_tag_mutability" {
  description = "Image tag mutability setting for the repository"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type to use for the repository"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "Encryption type must be either AES256 or KMS."
  }
}

variable "kms_key_id" {
  description = "KMS key ID to use for KMS encryption (only used if encryption_type is KMS)"
  type        = string
  default     = null
}

# Lifecycle Policy Configuration
variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy for the repository"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of tagged images to keep"
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Number of days after which untagged images expire"
  type        = number
  default     = 7
}

# Repository Policy
variable "repository_policy" {
  description = "JSON policy document for repository access (optional)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}