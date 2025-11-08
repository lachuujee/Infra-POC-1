output "file_system_id" {
  value = aws_efs_file_system.this.id
}

output "mount_target_id" {
  value = aws_efs_mount_target.mt.id
}

output "security_group_id" {
  value = aws_security_group.efs.id
}
