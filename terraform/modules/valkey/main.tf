resource "aws_security_group" "valkey" {
  name        = "${var.project}-${var.environment}-valkey-sg"
  description = "ElastiCache Valkey — allow access from EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
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

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.project}-${var.environment}-valkey"
  engine               = "valkey"
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.valkey7"
  engine_version       = "7.2"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.valkey.id]

  tags = { Name = "${var.project}-${var.environment}-valkey" }
}
