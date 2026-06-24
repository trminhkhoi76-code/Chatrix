# ---------------------------------------------------------------------------
# SSM Parameter Store
#
# Spring Boot's aws-parameterstore integration reads /chatrix/* automatically
# at startup (configured in application.yml: spring.config.import).
# Parameter names map directly to Spring properties after stripping the prefix.
#
# The chatrix-websocket Netty server reads JWT_SECRET via user_data.sh.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Secrets  (SecureString — encrypted with AWS managed KMS key)
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "db_password" {
  name        = "/chatrix/spring.datasource.password"
  description = "RDS MySQL password for chatrix-api"
  type        = "SecureString"
  value       = var.db_password

  tags = { Name = "${local.name_prefix}-db-password" }

  # Prevent Terraform from overwriting if changed outside Terraform (e.g. rotation)
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/chatrix/chatrix.jwt.secret"
  description = "HMAC-SHA JWT signing secret (shared by API and WebSocket)"
  type        = "SecureString"
  value       = var.jwt_secret

  tags = { Name = "${local.name_prefix}-jwt-secret" }

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "redis_password" {
  name        = "/chatrix/spring.data.redis.password"
  description = "ElastiCache Redis AUTH token for chatrix-api"
  type        = "SecureString"
  value       = var.redis_auth_token

  tags = { Name = "${local.name_prefix}-redis-password" }

  lifecycle {
    ignore_changes = [value]
  }
}

# ---------------------------------------------------------------------------
# Non-secret config  (String — infrastructure endpoints injected post-deploy)
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "db_url" {
  name        = "/chatrix/spring.datasource.url"
  description = "RDS JDBC URL for chatrix-api"
  type        = "String"
  value       = "jdbc:mysql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}?useSSL=true&requireSSL=true&serverTimezone=UTC"

  tags = { Name = "${local.name_prefix}-db-url" }
}

resource "aws_ssm_parameter" "redis_host" {
  name        = "/chatrix/spring.data.redis.host"
  description = "ElastiCache Redis primary endpoint"
  type        = "String"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address

  tags = { Name = "${local.name_prefix}-redis-host" }
}

resource "aws_ssm_parameter" "redis_ssl" {
  name        = "/chatrix/spring.data.redis.ssl.enabled"
  description = "Enable TLS for Redis (required because transit_encryption_enabled=true)"
  type        = "String"
  value       = "true"

  tags = { Name = "${local.name_prefix}-redis-ssl" }
}

resource "aws_ssm_parameter" "storage_upload_dir" {
  name        = "/chatrix/chatrix.storage.upload-dir"
  description = "Local disk path for file uploads on EC2"
  type        = "String"
  value       = "/var/chatrix/uploads"

  tags = { Name = "${local.name_prefix}-upload-dir" }
}

resource "aws_ssm_parameter" "storage_base_url" {
  name        = "/chatrix/chatrix.storage.base-url"
  description = "Public base URL for file download links"
  type        = "String"
  value       = var.acm_certificate_arn != "" && var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_lb.main.dns_name}"

  tags = { Name = "${local.name_prefix}-storage-base-url" }
}

# ---------------------------------------------------------------------------
# Schedule override  (managed by Lambda env_manager; writable by ops team)
# Values: none | force_on | force_off
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "schedule_override" {
  name        = "/chatrix/schedule/override"
  description = "Manual override for the start/stop schedule. Set via Lambda action=override or aws ssm put-parameter"
  type        = "String"
  value       = "none"

  tags = { Name = "${local.name_prefix}-schedule-override" }

  # Lambda updates this at runtime — ignore Terraform drift
  lifecycle {
    ignore_changes = [value]
  }
}
