output "web_acl_arn" {
  value       = try(aws_wafv2_web_acl.this[0].arn, null)
  description = "WAFv2 WebACL ARN."
}

output "web_acl_id" {
  value       = try(aws_wafv2_web_acl.this[0].id, null)
  description = "WAFv2 WebACL ID."
}

output "web_acl_name" {
  value       = try(aws_wafv2_web_acl.this[0].name, null)
  description = "WAFv2 WebACL name."
}

output "log_group_name" {
  value       = try(aws_cloudwatch_log_group.this[0].name, null)
  description = "CloudWatch log group for WAF logs."
}
