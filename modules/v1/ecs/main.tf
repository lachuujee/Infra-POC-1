# main.tf
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name_hyphen = lower(replace(var.name, "_", "-"))
  name_clean  = lower(replace(replace(replace(var.name, "_", ""), "-", ""), " ", ""))

  id20      = substr(local.name_hyphen, 0, 20)
  repo_name = endswith(local.name_hyphen, "-ecs") ? "${local.name_hyphen}-ecr" : "${local.name_hyphen}-ecs-ecr"

  tags_common = merge(
    var.common_tags,
    {
      Service   = "ecs_service"
      RequestID = var.request_id
    }
  )

  ports = {
    svc1 = 8091
    svc2 = 8092
    svc3 = 8093
  }

  svc1_enabled = var.service_count >= 1
  svc2_enabled = var.service_count >= 2
  svc3_enabled = var.service_count >= 3

  svc_keys = local.svc3_enabled ? ["svc1","svc2","svc3"] : local.svc2_enabled ? ["svc1","svc2"] : ["svc1"]
  svc_map  = { for k in local.svc_keys : k => local.ports[k] }
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = var.vpc_state_key
    region = var.remote_state_region
  }
}

data "terraform_remote_state" "alb" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = var.alb_state_key
    region = var.remote_state_region
  }
}

locals {
  vpc_id     = try(data.terraform_remote_state.vpc.outputs.vpc_id, null)
  alb_lb_arn = try(data.terraform_remote_state.alb.outputs.alb_lb_arn, "")

  roles           = try(data.terraform_remote_state.vpc.outputs.private_subnet_ids_by_role, {})
  api_a_subnet_id = try(local.roles["api-a"], "")
  api_b_subnet_id = try(local.roles["api-b"], "")
  api_subnet_ids  = [for x in [local.api_a_subnet_id, local.api_b_subnet_id] : x if length(x) > 0]

  log_group_names = { for k, p in local.svc_map : k => "/aws/ecs/${local.name_hyphen}-svc-${p}" }
}

data "aws_lb" "alb" {
  arn = local.alb_lb_arn
}

data "aws_subnet" "alb_subnets" {
  for_each = { for id in data.aws_lb.alb.subnets : id => id }
  id       = each.value
}

locals {
  alb_subnet_cidrs = [for s in data.aws_subnet.alb_subnets : s.cidr_block]
}

resource "aws_ecr_repository" "app" {
  name                 = length(var.ecr_repo_name_override) > 0 ? var.ecr_repo_name_override : local.repo_name
  image_tag_mutability = "MUTABLE"
  tags                 = local.tags_common
}

resource "aws_security_group" "tasks" {
  name        = "${local.name_hyphen}-ecs-sg"
  description = var.name
  vpc_id      = local.vpc_id
  tags        = merge(local.tags_common, { Name = "${var.name}_ecs_sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_alb_subnets_8091" {
  for_each          = local.svc1_enabled ? { for cidr in local.alb_subnet_cidrs : cidr => cidr } : {}
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = each.value
  from_port         = 8091
  to_port           = 8091
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_alb_subnets_8092" {
  for_each          = local.svc2_enabled ? { for cidr in local.alb_subnet_cidrs : cidr => cidr } : {}
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = each.value
  from_port         = 8092
  to_port           = 8092
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_alb_subnets_8093" {
  for_each          = local.svc3_enabled ? { for cidr in local.alb_subnet_cidrs : cidr => cidr } : {}
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = each.value
  from_port         = 8093
  to_port           = 8093
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.tasks.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_hyphen}-cluster"
  tags = local.tags_common
}

resource "aws_cloudwatch_log_group" "svc" {
  for_each          = local.svc_map
  name              = local.log_group_names[each.key]
  retention_in_days = var.log_retention_days
  tags              = local.tags_common
}

locals {
  image_effective = length(var.container_image) > 0 ? var.container_image : "${aws_ecr_repository.app.repository_url}:latest"
}

resource "aws_ecs_task_definition" "svc" {
  for_each                 = local.svc_map
  family                   = "${local.name_hyphen}-svc-${each.value}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gib
  }

  container_definitions = <<DEFS
[
  {
    "name": "app",
    "image": "${local.image_effective}",
    "essential": true,
    "portMappings": [
      {"containerPort": ${each.value}, "hostPort": ${each.value}, "protocol": "tcp"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.svc[each.key].name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
DEFS

  tags = local.tags_common
}

resource "aws_lb_target_group" "svc" {
  for_each    = local.svc_map
  name        = "${local.id20}-tg-${each.value}"
  port        = each.value
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"
  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }
  tags = local.tags_common
}

resource "aws_lb_listener" "svc" {
  for_each          = local.svc_map
  load_balancer_arn = local.alb_lb_arn
  port              = each.value
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }
  tags = local.tags_common
}

resource "aws_ecs_service" "svc" {
  for_each                = local.svc_map
  name                    = "${local.name_hyphen}-svc-${each.value}"
  cluster                 = aws_ecs_cluster.this.arn
  task_definition         = aws_ecs_task_definition.svc[each.key].arn
  desired_count           = 1
  launch_type             = "FARGATE"
  platform_version        = "LATEST"
  enable_execute_command  = false

  network_configuration {
    subnets         = local.api_subnet_ids
    security_groups = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.svc[each.key].arn
    container_name   = "app"
    container_port   = each.value
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.tags_common
}

resource "aws_iam_role" "execution" {
  name = "${local.name_hyphen}-exec-role"
  assume_role_policy = <<POL
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.${data.aws_partition.current.dns_suffix}"},
    "Action": "sts:AssumeRole"
  }]
}
POL
  tags = local.tags_common
}

resource "aws_iam_role_policy" "execution_min" {
  name = "${local.name_hyphen}-exec-pol"
  role = aws_iam_role.execution.id
  policy = <<POL
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect":"Allow","Action":["ecr:GetAuthorizationToken"],"Resource":"*"},
    {"Effect":"Allow","Action":["ecr:BatchCheckLayerAvailability","ecr:GetDownloadUrlForLayer","ecr:BatchGetImage"],"Resource":"*"},
    {"Effect":"Allow","Action":["logs:CreateLogStream","logs:PutLogEvents","logs:CreateLogGroup","logs:DescribeLogStreams"],"Resource":"*"}
  ]
}
POL
}

resource "aws_iam_role" "task" {
  name = "${local.name_hyphen}-task-role"
  assume_role_policy = <<POL
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.${data.aws_partition.current.dns_suffix}"},
    "Action": "sts:AssumeRole"
  }]
}
POL
  tags = local.tags_common
}

resource "aws_appautoscaling_target" "svc" {
  for_each           = local.svc_map
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.svc[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.svc_map
  name     = "${local.name_hyphen}-cpu-${each.value}"
  policy_type = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.svc[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.svc[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.svc[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "mem" {
  for_each = local.svc_map
  name     = "${local.name_hyphen}-mem-${each.value}"
  policy_type = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.svc[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.svc[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.svc[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
