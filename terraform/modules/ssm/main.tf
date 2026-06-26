resource "aws_ssm_parameter" "db_url" {
  name  = "/chatrix/spring.datasource.url"
  type  = "String"
  value = var.db_url
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/chatrix/spring.datasource.username"
  type  = "String"
  value = var.db_username
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/chatrix/spring.datasource.password"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/chatrix/chatrix.jwt.secret"
  type  = "SecureString"
  value = var.jwt_secret
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "/chatrix/spring.data.redis.host"
  type  = "String"
  value = var.redis_host
}

resource "aws_ssm_parameter" "redis_port" {
  name  = "/chatrix/spring.data.redis.port"
  type  = "String"
  value = var.redis_port
}

resource "aws_ssm_parameter" "redis_ssl" {
  name  = "/chatrix/spring.data.redis.ssl.enabled"
  type  = "String"
  value = "false"
}

resource "aws_ssm_parameter" "storage_base_url" {
  name  = "/chatrix/chatrix.storage.base-url"
  type  = "String"
  value = var.storage_base_url
}

resource "aws_ssm_parameter" "storage_upload_dir" {
  name  = "/chatrix/chatrix.storage.upload-dir"
  type  = "String"
  value = var.storage_upload_dir
}
