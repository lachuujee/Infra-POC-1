# outputs.f
output "namespace_name" {
  value = aws_redshiftserverless_namespace.this.namespace_name
}

output "workgroup_name" {
  value = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_arn" {
  value = aws_redshiftserverless_workgroup.this.arn
}

output "workgroup_id" {
  value = aws_redshiftserverless_workgroup.this.id
}

output "security_group_id" {
  value = aws_security_group.redshift.id
}

output "endpoint_address" {
  value = try(aws_redshiftserverless_workgroup.this.endpoint[0].address, null)
}

output "endpoint_port" {
  value = try(aws_redshiftserverless_workgroup.this.endpoint[0].port, null)
}

output "db_name" {
  value = "dev"
}

output "default_iam_role_arn" {
  value = aws_iam_role.redshift_default.arn
}

output "selected_subnet_ids" {
  value = local.db_subnets_final
}

output "admin_password_secret_arn" {
  value = try(aws_redshiftserverless_namespace.this.admin_password_secret_arn, null)
}
