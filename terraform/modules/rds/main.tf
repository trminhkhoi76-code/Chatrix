resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "RDS MySQL - allow access from EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-rds-sg" }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.project}-${var.environment}-db-subnet-group" }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.project}-${var.environment}-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = { Name = "${var.project}-${var.environment}-mysql8" }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project}-${var.environment}-mysql"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = var.db_username
  password       = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az            = false
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  tags = { Name = "${var.project}-${var.environment}-mysql" }
}
