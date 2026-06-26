terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }

  required_version = ">= 1.5"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ── VPC ───────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ── ECR ───────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment
  services    = ["api", "websocket"]
}

# ── ALB ───────────────────────────────────────────────────────────────────────

module "alb" {
  source = "../../modules/alb"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "alb_websocket" {
  source = "../../modules/alb-target-group"

  project      = var.project
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  listener_arn = module.alb.http_listener_arn
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

module "ecs" {
  source = "../../modules/ecs"

  project     = var.project
  environment = var.environment
}

# ── ECS Services ──────────────────────────────────────────────────────────────

module "ecs_api" {
  source = "../../modules/ecs-service"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  service_name = "api"

  cluster_id            = module.ecs.cluster_id
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.api_target_group_arn
  execution_role_arn    = module.ecs.execution_role_arn
  log_group_name        = module.ecs.log_group_name

  image_uri      = "${module.ecr.repository_urls["api"]}:latest"
  container_port = 8080

  # 0.5 vCPU / 1 GB — minimum viable for Spring Boot; ~$12/month Fargate Spot
  task_cpu    = 512
  task_memory = 1024
}

module "ecs_websocket" {
  source = "../../modules/ecs-service"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  service_name = "websocket"

  cluster_id            = module.ecs.cluster_id
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb_websocket.target_group_arn
  execution_role_arn    = module.ecs.execution_role_arn
  log_group_name        = module.ecs.log_group_name

  image_uri      = "${module.ecr.repository_urls["websocket"]}:latest"
  container_port = 8081

  # 0.25 vCPU / 512 MB — Netty is lightweight; ~$6/month Fargate Spot
  task_cpu    = 256
  task_memory = 512
}