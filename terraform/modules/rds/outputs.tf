output "endpoint" {
  description = "RDS endpoint hostname (without port)"
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
