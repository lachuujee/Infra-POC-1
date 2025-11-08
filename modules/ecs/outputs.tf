output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "service_arns" {
  value = {
    for k, s in aws_ecs_service.svc :
    k => "arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${s.name}"
  }
}

output "task_definition_arns" {
  value = { for k, t in aws_ecs_task_definition.svc : k => t.arn }
}

output "target_group_arns" {
  value = { for k, tg in aws_lb_target_group.svc : k => tg.arn }
}

output "listener_arns" {
  value = { for k, l in aws_lb_listener.svc : k => l.arn }
}

output "security_group_id" {
  value = aws_security_group.tasks.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "log_group_names" {
  value = { for k, lg in aws_cloudwatch_log_group.svc : k => lg.name }
}

output "alb_lb_arn" {
  value = local.alb_lb_arn
}

output "api_subnet_ids_used" {
  value = local.api_subnet_ids
}
