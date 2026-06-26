# Security group — only accepts traffic from the ALB
resource "aws_security_group" "task" {
  name        = "${var.project}-${var.environment}-${var.service_name}-task-sg"
  description = "ECS Fargate tasks — ${var.service_name}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ALB → task"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-${var.service_name}-task-sg" }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project}-${var.environment}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([{
    name      = var.service_name
    image     = var.image_uri
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [for k, v in var.environment_variables : { name = k, value = v }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = var.service_name
      }
    }

    # Give Spring Boot / Netty time to start before health checks begin
    startTimeout = 120
    stopTimeout  = 30
  }])

  tags = { Name = "${var.project}-${var.environment}-${var.service_name}" }
}

resource "aws_ecs_service" "this" {
  name            = "${var.project}-${var.environment}-${var.service_name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # avoids NAT Gateway cost; SG restricts inbound to ALB only
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  lifecycle {
    # CI/CD (build-push-ecr workflow) updates the image; ignore to prevent drift
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.project}-${var.environment}-${var.service_name}" }
}
