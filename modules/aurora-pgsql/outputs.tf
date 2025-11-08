output "cluster_id" {
  value       = aws_rds_cluster.this.id
  description = "Aurora cluster identifier"
}

output "cluster_arn" {
  value       = aws_rds_cluster.this.arn
  description = "Aurora cluster ARN"
}

output "endpoint" {
  value       = aws_rds_cluster.this.endpoint
  description = "Writer endpoint"
}

output "reader_endpoint" {
  value       = aws_rds_cluster.this.reader_endpoint
  description = "Reader endpoint"
}

output "master_user_secret_arn" {
  value       = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
  description = "Secrets Manager ARN for master user"
}

output "db_name" {
  value       = aws_rds_cluster.this.database_name
  description = "Initial database name"
}

output "vpc_security_group_id" {
  value       = aws_security_group.aurora.id
  description = "Created security group ID"
}

output "vpc_security_group_name" {
  value       = aws_security_group.aurora.name
  description = "Created security group name"
}

output "db_subnet_group" {
  value       = aws_db_subnet_group.this.name
  description = "DB subnet group name"
}
