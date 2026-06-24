# ---------------------------------------------------------------------------
# ElastiCache Redis  (single node, TLS + AUTH, no replica — cheapest config)
#
# NOTE: transit_encryption_enabled = true requires the Spring Boot app to
# connect via TLS. Add to application.yml (or SSM):
#   spring.data.redis.ssl.enabled: true
# ---------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "main" {
  name        = "${local.name_prefix}-redis-subnet-group"
  description = "Private subnets for ElastiCache"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${local.name_prefix}-redis-subnet-group" }
}

resource "aws_elasticache_parameter_group" "redis7" {
  name        = "${local.name_prefix}-redis"
  family      = var.redis_parameter_group_family
  description = "Chatrix Redis ${var.redis_engine_version} parameters"

  # Disable persistence (AOF/RDB) — saves IOPS; sessions are ephemeral anyway
  parameter {
    name  = "appendonly"
    value = "no"
  }

  tags = { Name = "${local.name_prefix}-redis7-params" }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "Chatrix Redis cache"

  node_type          = var.redis_node_type
  num_cache_clusters = 1   # Single node — no failover, cheapest option
  port               = var.redis_port

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  parameter_group_name = aws_elasticache_parameter_group.redis7.name

  engine_version = var.redis_engine_version

  # Security
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true # Required for auth_token
  auth_token                 = var.redis_auth_token

  # Cost optimizations
  automatic_failover_enabled = false # Requires num_cache_clusters >= 2
  multi_az_enabled           = false

  # Maintenance
  maintenance_window       = "sun:20:00-sun:21:00" # UTC
  snapshot_retention_limit = 1                     # Keep 1 daily snapshot (free up to 1 per cluster)
  snapshot_window          = "17:00-18:00"         # UTC

  apply_immediately = false

  tags = { Name = "${local.name_prefix}-redis" }
}
