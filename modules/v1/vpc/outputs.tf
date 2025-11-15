output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID"
}

output "vpc_cidr_block" {
  value       = aws_vpc.this.cidr_block
  description = "VPC CIDR"
}

output "public_subnet_ids" {
  value       = [for k, s in aws_subnet.public : s.id]
  description = "Public subnet IDs"
}

output "private_subnet_ids" {
  value       = [for k, s in aws_subnet.private : s.id]
  description = "Private subnet IDs"
}

output "private_subnet_ids_by_role" {
  value       = { for k, s in aws_subnet.private : k => s.id }
  description = "Map of private subnets by role key (e.g., app-a, api-b, db-a)"
}
