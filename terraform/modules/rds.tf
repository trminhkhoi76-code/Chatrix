# ---------------------------------------------------------------------------
# RDS MySQL  (Single-AZ, gp2 storage — cheapest viable config)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Private subnets for RDS"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${local.name_prefix}-db-subnet-group" }
}

resource "aws_db_parameter_group" "mysql8" {
  name        = "${local.name_prefix}-mysql"
  family      = var.db_parameter_group_family
  description = "Chatrix MySQL ${var.db_engine_version} parameters"

  # UTF-8 full unicode (emoji support)
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # Disable slow-query log by default (enable for debugging)
  parameter {
    name  = "slow_query_log"
    value = "0"
  }

  tags = { Name = "${local.name_prefix}-mysql8-params" }
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-mysql"

  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = 100 # Autoscaling up to 100 GB
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql8.name

  # Cost optimizations
  multi_az                     = false # No standby replica
  publicly_accessible          = false
  performance_insights_enabled = false # Saves ~$0/month (free tier), but disable for cost clarity
  monitoring_interval          = 0     # No enhanced monitoring (saves ~$0.05/metric/month)
  enabled_cloudwatch_logs_exports = [] # No RDS log export (use app-level logging instead)

  # Backups
  backup_retention_period = 7
  backup_window           = "18:00-19:00" # UTC — midnight JST
  maintenance_window      = "sun:19:00-sun:20:00"

  # Lifecycle
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-mysql-final"
  copy_tags_to_snapshot     = true

  apply_immediately = false

  tags = { Name = "${local.name_prefix}-mysql" }
}
