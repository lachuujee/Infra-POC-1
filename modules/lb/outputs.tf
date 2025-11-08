output "security_group_id" {
  value       = length(aws_security_group.alb_sg) > 0 ? aws_security_group.alb_sg[0].id : null
  description = "ALB security group ID"
}

output "alb_lb_arn" {
  value       = length(aws_lb.alb) > 0 ? aws_lb.alb[0].arn : null
  description = "ALB ARN"
}

output "alb_lb_dns_name" {
  value       = length(aws_lb.alb) > 0 ? aws_lb.alb[0].dns_name : null
  description = "ALB DNS name"
}

output "alb_lb_zone_id" {
  value       = length(aws_lb.alb) > 0 ? aws_lb.alb[0].zone_id : null
  description = "ALB hosted zone ID"
}

output "alb_tg_arn" {
  value       = length(aws_lb_target_group.alb) > 0 ? aws_lb_target_group.alb[0].arn : null
  description = "ALB target group ARN"
}

output "nlb_lb_arn" {
  value       = length(aws_lb.nlb) > 0 ? aws_lb.nlb[0].arn : null
  description = "NLB ARN"
}

output "nlb_lb_dns_name" {
  value       = length(aws_lb.nlb) > 0 ? aws_lb.nlb[0].dns_name : null
  description = "NLB DNS name"
}

output "nlb_lb_zone_id" {
  value       = length(aws_lb.nlb) > 0 ? aws_lb.nlb[0].zone_id : null
  description = "NLB hosted zone ID"
}

output "nlb_tg_arn" {
  value       = length(aws_lb_target_group.nlb) > 0 ? aws_lb_target_group.nlb[0].arn : null
  description = "NLB target group ARN"
}

output "access_logs_bucket_alb" {
  value       = length(aws_s3_bucket.alb_logs) > 0 ? aws_s3_bucket.alb_logs[0].bucket : null
  description = "ALB access-logs bucket"
}

output "access_logs_bucket_nlb" {
  value       = length(aws_s3_bucket.nlb_logs) > 0 ? aws_s3_bucket.nlb_logs[0].bucket : null
  description = "NLB access-logs bucket"
}

output "listener_port_used" {
  value       = var.listener_port
  description = "Listener port"
}

output "tg_port_used" {
  value       = var.tg_port
  description = "Target group port"
}
