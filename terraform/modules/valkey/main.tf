resource "aws_security_group" "valkey" {
  name        = "${var.project}-${var.environment}-valkey-sg"
  description = "ElastiCache Valkey - allow inbound from ECS tasks"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port       = 6379
      to_port         = 6379
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Valkey access from ${ingress.key == 0 ? "primary" : "additional"} ECS SG"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-valkey-sg" }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-valkey-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.project}-${var.environment}-valkey-subnet-group" }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-${var.environment}-valkey"
  description          = "${var.project} ${var.environment} Valkey cluster"

  engine               = "valkey"
  engine_version       = "8.2"
  node_type            = var.node_type
  parameter_group_name = "default.valkey8"
  port                 = 6379

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.valkey.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  tags = { Name = "${var.project}-${var.environment}-valkey" }
}