output "security_group_id" {
  value       = length(aws_security_group.app_sg) > 0 ? aws_security_group.app_sg[0].id : null
  description = "EC2 SG ID"
}

output "instance_ids" {
  value       = [for i in aws_instance.app : i.id]
  description = "Launched instance IDs"
}

output "private_ips" {
  value       = [for i in aws_instance.app : i.private_ip]
  description = "Launched instance private IPs"
}

output "effective_ami" {
  value       = local.effective_ami
  description = "AMI actually used for launch"
  sensitive   = true
}

output "key_name_used" {
  value       = local.key_name
  description = "KeyPair name used (if any)"
}

output "iam_profile_used" {
  value       = local.iam_instance_profile
  description = "IAM instance profile used (if any)"
}
