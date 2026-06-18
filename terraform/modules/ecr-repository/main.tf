# ECR Repository Module
# Creates a single ECR repository for HeatmapJapanConsole

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_id : null
  }

  tags = {
    Name = var.repository_name
  }
}

# Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.enable_lifecycle_policy ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} images with ${var.environment} prefix"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = [var.environment]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Repository Policy (optional)
resource "aws_ecr_repository_policy" "this" {
  count      = var.repository_policy != null && var.repository_policy != "" ? 1 : 0
  repository = aws_ecr_repository.this.name
  policy     = var.repository_policy
}