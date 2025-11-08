data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = var.vpc_state_key
    region = var.remote_state_region
  }
}

locals {
  alb_name_clean  = replace(var.alb_name, "_", "-")
  nlb_name_clean  = replace(var.nlb_name, "_", "-")

  alb_tg_name     = substr("${local.alb_name_clean}-tg", 0, 32)
  nlb_tg_name     = substr("${local.nlb_name_clean}-tg", 0, 32)

  alb_logs_bucket = substr("${lower(local.alb_name_clean)}-access-logs", 0, 63)
  nlb_logs_bucket = substr("${lower(local.nlb_name_clean)}-access-logs", 0, 63)

  private_app_subnets = [
    data.terraform_remote_state.vpc.outputs.private_subnet_ids_by_role["app-a"],
    data.terraform_remote_state.vpc.outputs.private_subnet_ids_by_role["app-b"]
  ]
}

# ALB logging bucket
resource "aws_s3_bucket" "alb_logs" {
  count         = var.alb_enabled ? 1 : 0
  bucket        = local.alb_logs_bucket
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count  = var.alb_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  count  = var.alb_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = var.alb_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  count = var.alb_enabled ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    resources = [
      "${aws_s3_bucket.alb_logs[0].arn}/${local.alb_name_clean}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.alb_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json
}

# NLB logging bucket
resource "aws_s3_bucket" "nlb_logs" {
  count         = var.nlb_enabled ? 1 : 0
  bucket        = local.nlb_logs_bucket
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "nlb_logs" {
  count  = var.nlb_enabled ? 1 : 0
  bucket = aws_s3_bucket.nlb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "nlb_logs" {
  count  = var.nlb_enabled ? 1 : 0
  bucket = aws_s3_bucket.nlb_logs[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "nlb_logs" {
  count  = var.nlb_enabled ? 1 : 0
  bucket = aws_s3_bucket.nlb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "nlb_logs" {
  count = var.nlb_enabled ? 1 : 0

  statement {
    sid     = "AWSLogDeliveryAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [aws_s3_bucket.nlb_logs[0].arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid     = "AWSLogDeliveryWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [
      "${aws_s3_bucket.nlb_logs[0].arn}/${local.nlb_name_clean}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "nlb_logs" {
  count  = var.nlb_enabled ? 1 : 0
  bucket = aws_s3_bucket.nlb_logs[0].id
  policy = data.aws_iam_policy_document.nlb_logs[0].json
}

# ALB SG
resource "aws_security_group" "alb_sg" {
  count       = var.alb_enabled ? 1 : 0
  name        = "${local.alb_name_clean}-sg"
  description = "${local.alb_name_clean}-sg"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  tags        = merge(local.common_tags, { Name = "${local.alb_name_clean}-sg" })
}

resource "aws_security_group_rule" "alb_ingress" {
  for_each          = var.alb_enabled ? { for i, r in var.alb_ingress_rules : tostring(i) => r } : {}
  type              = "ingress"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = "tcp"
  cidr_blocks       = each.value.cidrs
  security_group_id = aws_security_group.alb_sg[0].id
}

resource "aws_security_group_rule" "alb_egress_all" {
  count             = var.alb_enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg[0].id
}

# NLB SG (attached to NLB)
resource "aws_security_group" "nlb_sg" {
  count       = var.nlb_enabled ? 1 : 0
  name        = "${local.nlb_name_clean}-sg"
  description = "${local.nlb_name_clean}-sg"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  tags        = merge(local.common_tags, { Name = "${local.nlb_name_clean}-sg" })
}

resource "aws_security_group_rule" "nlb_ingress" {
  for_each          = var.nlb_enabled ? { for i, r in var.alb_ingress_rules : tostring(i) => r } : {}
  type              = "ingress"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = "tcp"
  cidr_blocks       = each.value.cidrs
  security_group_id = aws_security_group.nlb_sg[0].id
}

resource "aws_security_group_rule" "nlb_egress_all" {
  count             = var.nlb_enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb_sg[0].id
}

# ALB
resource "aws_lb" "alb" {
  count                      = var.alb_enabled ? 1 : 0
  name                       = local.alb_name_clean
  load_balancer_type         = "application"
  internal                   = var.public ? false : true
  subnets                    = var.public ? data.terraform_remote_state.vpc.outputs.public_subnet_ids : local.private_app_subnets
  security_groups            = [aws_security_group.alb_sg[0].id]
  drop_invalid_header_fields = true
  tags                       = merge(local.common_tags, { Name = local.alb_name_clean })

  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.alb_logs[0].bucket
    prefix  = local.alb_name_clean
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "alb" {
  count       = var.alb_enabled ? 1 : 0
  name        = local.alb_tg_name
  port        = var.tg_port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  target_type = var.target_type
  tags        = merge(local.common_tags, { Name = local.alb_tg_name })

  health_check {
    enabled  = true
    path     = "/healthz"
    protocol = "HTTP"
  }
}

resource "aws_lb_listener" "alb_http" {
  count             = var.alb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.alb[0].arn
  port              = var.listener_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb[0].arn
  }
}

# NLB
resource "aws_lb" "nlb" {
  count              = var.nlb_enabled ? 1 : 0
  name               = local.nlb_name_clean
  load_balancer_type = "network"
  internal           = var.public ? false : true
  subnets            = var.public ? data.terraform_remote_state.vpc.outputs.public_subnet_ids : local.private_app_subnets
  security_groups    = [aws_security_group.nlb_sg[0].id]
  tags               = merge(local.common_tags, { Name = local.nlb_name_clean })

  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.nlb_logs[0].bucket
    prefix  = local.nlb_name_clean
  }

  depends_on = [aws_s3_bucket_policy.nlb_logs]
}

resource "aws_lb_target_group" "nlb" {
  count       = var.nlb_enabled ? 1 : 0
  name        = local.nlb_tg_name
  port        = var.tg_port
  protocol    = var.tg_protocol
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  target_type = var.target_type
  tags        = merge(local.common_tags, { Name = local.nlb_tg_name })

  health_check {
    enabled  = true
    protocol = var.tg_protocol
  }
}

resource "aws_lb_listener" "nlb_tcp" {
  count             = var.nlb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.nlb[0].arn
  port              = var.listener_port
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb[0].arn
  }
}

resource "aws_lb_target_group_attachment" "alb_ec2" {
  for_each         = var.alb_enabled && length(var.attach_instance_ids) > 0 ? toset(var.attach_instance_ids) : []
  target_group_arn = aws_lb_target_group.alb[0].arn
  target_id        = each.value
  port             = var.tg_port
}

resource "aws_autoscaling_attachment" "alb_asg" {
  count                  = var.alb_enabled && var.asg_name != "" ? 1 : 0
  autoscaling_group_name = var.asg_name
  lb_target_group_arn    = aws_lb_target_group.alb[0].arn
}

resource "aws_lb_target_group_attachment" "nlb_ec2" {
  for_each         = var.nlb_enabled && length(var.attach_instance_ids) > 0 ? toset(var.attach_instance_ids) : []
  target_group_arn = aws_lb_target_group.nlb[0].arn
  target_id        = each.value
  port             = var.tg_port
}

resource "aws_autoscaling_attachment" "nlb_asg" {
  count                  = var.nlb_enabled && var.asg_name != "" ? 1 : 0
  autoscaling_group_name = var.asg_name
  lb_target_group_arn    = aws_lb_target_group.nlb[0].arn
}
