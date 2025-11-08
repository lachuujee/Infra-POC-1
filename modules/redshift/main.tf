# main.f
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name_hyphen   = replace(var.name, "_", "-")
  identifier    = local.name_hyphen
  simple_name   = substr(replace(replace(replace(var.name, "_", ""), "-", ""), " ", ""), 0, 63)
  redshift_port = 5439
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = var.vpc_state_key
    region = var.remote_state_region
  }
}

locals {
  vpc_id          = try(data.terraform_remote_state.vpc.outputs.vpc_id, null)
  subnets_by_name = try(data.terraform_remote_state.vpc.outputs.subnets_by_name, {})

  db_subnets_from_names = [
    for k, id in local.subnets_by_name :
    id if endswith(lower(k), "-private-db-a") || endswith(lower(k), "-private-db-b") || endswith(lower(k), "-private-db-c")
  ]

  db_subnets_alt = try(
    data.terraform_remote_state.vpc.outputs.db_subnet_ids,
    try(
      data.terraform_remote_state.vpc.outputs.private_db_subnet_ids,
      data.terraform_remote_state.vpc.outputs.private_subnet_ids
    )
  )

  db_subnets_final = length(var.subnet_ids) > 0 ? var.subnet_ids : (length(local.db_subnets_from_names) > 0 ? local.db_subnets_from_names : local.db_subnets_alt)

  api_subnet_ids_from_names = [
    for k, id in local.subnets_by_name :
    id if endswith(lower(k), "-private-api-a") || endswith(lower(k), "-private-api-b") || endswith(lower(k), "-private-api-c")
  ]
}

data "aws_subnet" "api" {
  for_each = { for id in local.api_subnet_ids_from_names : id => id }
  id       = each.value
}

locals {
  api_cidrs = [for _, s in data.aws_subnet.api : s.cidr_block]
}

resource "aws_security_group" "redshift" {
  name        = "${local.identifier}-redshift-sg"
  description = local.identifier
  vpc_id      = local.vpc_id
  tags        = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "redshift_in_api" {
  for_each          = { for cidr in local.api_cidrs : cidr => cidr }
  security_group_id = aws_security_group.redshift.id
  cidr_ipv4         = each.value
  from_port         = local.redshift_port
  to_port           = local.redshift_port
  ip_protocol       = "tcp"
  description       = "api subnets"
}

resource "aws_vpc_security_group_ingress_rule" "redshift_in_cidrs" {
  for_each                = { for cidr in var.allowed_cidr_blocks : cidr => cidr }
  security_group_id       = aws_security_group.redshift.id
  cidr_ipv4               = each.value
  from_port               = local.redshift_port
  to_port                 = local.redshift_port
  ip_protocol             = "tcp"
  description             = "allowed cidr blocks"
}

resource "aws_vpc_security_group_ingress_rule" "redshift_in_sg" {
  for_each                      = { for sg in var.allowed_security_group_ids : sg => sg }
  security_group_id             = aws_security_group.redshift.id
  referenced_security_group_id  = each.value
  from_port                     = local.redshift_port
  to_port                       = local.redshift_port
  ip_protocol                   = "tcp"
  description                   = "allowed security groups"
}

resource "aws_vpc_security_group_egress_rule" "redshift_out_all" {
  security_group_id = aws_security_group.redshift.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "all outbound"
}

resource "aws_iam_role" "redshift_default" {
  name = "${local.identifier}-redshift-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "redshift.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy" "redshift_s3_rw" {
  name = "${local.identifier}-s3-rw"
  role = aws_iam_role.redshift_default.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = ["arn:${data.aws_partition.current.partition}:s3:::*"]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucketMultipartUploads"],
        Resource = ["arn:${data.aws_partition.current.partition}:s3:::*/*"]
      }
    ]
  })
}

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name        = local.identifier
  db_name               = "dev"
  admin_username        = local.simple_name
  manage_admin_password = true
  default_iam_role_arn  = aws_iam_role.redshift_default.arn
  iam_roles             = [aws_iam_role.redshift_default.arn]
  log_exports           = ["userlog", "connectionlog", "useractivitylog"]
  tags                  = var.common_tags
}

resource "aws_redshiftserverless_workgroup" "this" {
  workgroup_name       = local.identifier
  namespace_name       = aws_redshiftserverless_namespace.this.namespace_name
  base_capacity        = var.base_rpus
  max_capacity         = var.max_rpus
  subnet_ids           = local.db_subnets_final
  security_group_ids   = [aws_security_group.redshift.id]
  publicly_accessible  = false
  enhanced_vpc_routing = false
  tags                 = var.common_tags

  lifecycle {
    precondition {
      condition     = length(local.db_subnets_final) >= 2
      error_message = "At least two private subnets in different AZs are required when Enhanced VPC routing is disabled."
    }
  }
}

resource "aws_secretsmanager_secret" "redshift_info" {
  name = "${local.identifier}-secret"
  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "redshift_info_v" {
  secret_id     = aws_secretsmanager_secret.redshift_info.id
  secret_string = jsonencode({
    engine                    = "redshift-serverless",
    port                      = local.redshift_port,
    namespace                 = aws_redshiftserverless_namespace.this.namespace_name,
    db_name                   = "dev",
    admin_username            = aws_redshiftserverless_namespace.this.admin_username,
    admin_password_secret_arn = try(aws_redshiftserverless_namespace.this.admin_password_secret_arn, null),
    workgroup_name            = aws_redshiftserverless_workgroup.this.workgroup_name,
    workgroup_arn             = aws_redshiftserverless_workgroup.this.arn,
    endpoints                 = try([for e in aws_redshiftserverless_workgroup.this.endpoint : e.address], []),
    endpoint_ports            = try([for e in aws_redshiftserverless_workgroup.this.endpoint : e.port], []),
    security_group_id         = aws_security_group.redshift.id,
    subnets                   = local.db_subnets_final
  })
}
