output "redis_replication_group_id" {
  value = aws_elasticache_replication_group.redis.id
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  value = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "redis_port" {
  value = var.port
}

output "redis_security_group_id" {
  value = aws_security_group.cache.id
}

output "redis_subnet_group_name" {
  value = aws_elasticache_subnet_group.cache.name
}

output "redis_subnet_ids_used" {
  value = local.cache_subnet_ids
}

output "redis_secret_name" {
  value = aws_secretsmanager_secret.cache.name
}

output "redis_secret_arn" {
  value = aws_secretsmanager_secret.cache.arn
}
