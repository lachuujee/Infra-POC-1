output "role_name" {
  value       = var.enabled ? aws_iam_role.this[0].name : null
  description = "Role name"
}

output "role_arn" {
  value       = var.enabled ? aws_iam_role.this[0].arn : null
  description = "Role ARN"
}

output "instance_profile_name" {
  value       = var.enabled ? aws_iam_instance_profile.this[0].name : null
  description = "Instance profile name"
}

output "instance_profile_arn" {
  value       = var.enabled ? aws_iam_instance_profile.this[0].arn : null
  description = "Instance profile ARN"
}
