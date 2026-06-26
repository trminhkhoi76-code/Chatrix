output "endpoint" {
  description = "Valkey primary endpoint hostname"
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "port" {
  value = aws_elasticache_cluster.this.cache_nodes[0].port
}

output "security_group_id" {
  value = aws_security_group.valkey.id
}
