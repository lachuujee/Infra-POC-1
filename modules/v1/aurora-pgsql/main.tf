data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name_hyphen   = replace(var.name, "_", "-")
  db_identifier = local.name_hyphen
  simple_name   = substr(replace(replace(replace(var.name, "_", ""), "-", ""), " ", ""), 0, 63)
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
  vpc_cidr        = try(data.terraform_remote_state.vpc.outputs.vpc_cidr, null)
  subnets_by_name = try(data.terraform_remote_state.vpc.outputs.subnets_by_name, {})

  db_a = try([for k, id in local.subnets_by_name : id if endswith(lower(k), "-private-db-a")][0], null)
  db_b = try([for k, id in local.subnets_by_name : id if endswith(lower(k), "-private-db-b")][0], null)
  db_subnets_from_names = compact([local.db_a, local.db_b])
  db_subnets_alt        = try(
    data.terraform_remote_state.vpc.outputs.db_subnet_ids,
    try(data.terraform_remote_state.vpc.outputs.private_db_subnet_ids,
        data.terraform_remote_state.vpc.outputs.private_subnet_ids)
  )
  db_subnets_final = length(local.db_subnets_from_names) > 0 ? local.db_subnets_from_names : local.db_subnets_alt

  api_a = try([for k, id in local.subnets_by_name : id if endswith(lower(k), "-private-api-a")][0], null)
  api_b = try([for k, id in local.subnets_by_name : id if endswith(lower(k), "-private-api-b")][0], null)
  api_subnet_ids_from_names = compact([local.api_a, local.api_b])
}

data "aws_subnet" "api" {
  for_each = toset(local.api_subnet_ids_from_names)
  id       = each.value
}

locals {
  api_cidrs = [for s in data.aws_subnet.api : s.cidr_block]
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.db_identifier}-db-subnets"
  description = local.db_identifier
  subnet_ids  = local.db_subnets_final
  tags        = var.common_tags
}

resource "aws_security_group" "aurora" {
  name        = "${local.db_identifier}-aurora-rds-sg"
  description = local.db_identifier
  vpc_id      = local.vpc_id
  tags        = merge(var.common_tags, { Name = "${var.name}-aurora-rds-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "aurora_in_api" {
  for_each          = toset(local.api_cidrs)
  security_group_id = aws_security_group.aurora.id
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "api subnets"
}

resource "aws_vpc_security_group_egress_rule" "aurora_out_all" {
  security_group_id = aws_security_group.aurora.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "all outbound"
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "Aurora-RDS-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "monitoring.rds.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_em_attach" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = local.db_identifier
  engine                              = "aurora-postgresql"
  manage_master_user_password         = true
  master_username                     = local.simple_name
  database_name                       = local.simple_name
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.aurora.id]
  port                                = var.port
  iam_database_authentication_enabled = true
  enable_http_endpoint                = true
  storage_encrypted                   = true
  backup_retention_period             = 7
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
  serverlessv2_scaling_configuration {
    min_capacity = var.serverlessv2_min_acu
    max_capacity = var.serverlessv2_max_acu
  }
  tags = var.common_tags
}

resource "aws_rds_cluster_instance" "writer" {
  identifier                            = "${local.db_identifier}-writer"
  cluster_identifier                    = aws_rds_cluster.this.id
  engine                                = aws_rds_cluster.this.engine
  instance_class                        = "db.serverless"
  availability_zone                     = var.preferred_az
  publicly_accessible                   = false
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  tags = var.common_tags
}
