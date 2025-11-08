data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name_hyphen      = lower(replace(var.name, "_", "-"))
  cache_identifier = substr(local.name_hyphen, 0, 40)
  name_clean       = lower(replace(replace(replace(var.name, "_", ""), "-", ""), " ", ""))
  tags_common = {
    Name        = var.name
    Service     = "redis_cache"
    Environment = var.env
    RequestID   = var.request_id
  }
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
  roles = try(data.terraform_remote_state.vpc.outputs.private_subnet_ids_by_role, {})

  db_a_raw = try(local.roles["db-a"], "")
  db_b_raw = try(local.roles["db-b"], "")
  db_ids_from_roles = [for x in [local.db_a_raw, local.db_b_raw] : x if length(x) > 0]

  api_a_raw = try(local.roles["api-a"], "")
  api_b_raw = try(local.roles["api-b"], "")
  api_ids_from_roles = [for x in [local.api_a_raw, local.api_b_raw] : x if length(x) > 0]

  cache_subnet_ids = length(var.subnet_ids_override) > 0 ? var.subnet_ids_override : local.db_ids_from_roles
  api_subnet_ids   = length(var.api_subnet_ids) > 0 ? var.api_subnet_ids : local.api_ids_from_roles

  redis_port                 = var.port
  num_nodes                  = 1 + (var.replicas_per_node_group > 0 ? var.replicas_per_node_group : 0)
  engine_id                  = var.cache_engine == "valkey" ? "valkey" : "redis"
  auth_token_effective       = lower(join("-", [var.request_id, substr(local.name_clean, 0, 8), "p1!"]))
}

data "aws_subnet" "api" {
  for_each = { for id in local.api_subnet_ids : id => id }
  id       = each.value
}

locals {
  vpc_id    = try(data.terraform_remote_state.vpc.outputs.vpc_id, null)
  api_cidrs = [for s in data.aws_subnet.api : s.cidr_block]
}

resource "aws_elasticache_subnet_group" "cache" {
  name       = "${local.cache_identifier}-subnets"
  subnet_ids = local.cache_subnet_ids
  tags       = local.tags_common
}

resource "aws_security_group" "cache" {
  name        = "${local.cache_identifier}-cache-sg"
  description = var.name
  vpc_id      = local.vpc_id
  tags        = merge(local.tags_common, { Name = "${var.name}_cache_sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_api" {
  for_each          = { for cidr in local.api_cidrs : cidr => cidr }
  security_group_id = aws_security_group.cache.id
  cidr_ipv4         = each.value
  from_port         = local.redis_port
  to_port           = local.redis_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cidrs" {
  for_each          = { for cidr in var.allowed_cidr_blocks : cidr => cidr }
  security_group_id = aws_security_group.cache.id
  cidr_ipv4         = each.value
  from_port         = local.redis_port
  to_port           = local.redis_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sgs" {
  for_each                    = { for sg in var.allowed_security_group_ids : sg => sg }
  security_group_id           = aws_security_group.cache.id
  referenced_security_group_id = each.value
  from_port                   = local.redis_port
  to_port                     = local.redis_port
  ip_protocol                 = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.cache.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = local.cache_identifier
  description                = var.name
  engine                     = local.engine_id
  engine_version             = var.engine_version
  parameter_group_name       = var.parameter_group_name
  node_type                  = var.node_type
  port                       = local.redis_port
  subnet_group_name          = aws_elasticache_subnet_group.cache.name
  security_group_ids         = [aws_security_group.cache.id]
  num_cache_clusters         = local.num_nodes
  automatic_failover_enabled = local.num_nodes > 1 ? true : false
  multi_az_enabled           = var.multi_az_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  maintenance_window         = var.maintenance_window
  snapshot_window            = var.snapshot_window
  snapshot_retention_limit   = var.snapshot_retention_limit
  auth_token                 = local.auth_token_effective
  tags                       = local.tags_common
}

locals {
  primary_endpoint   = aws_elasticache_replication_group.redis.primary_endpoint_address
  reader_endpoint    = aws_elasticache_replication_group.redis.reader_endpoint_address
  engine_ver_actual  = coalesce(var.engine_version, aws_elasticache_replication_group.redis.engine_version)
  subnets_csv        = join(",", local.cache_subnet_ids)
  secret_payload     = "{\"engine\":\"${local.engine_id}\",\"engine_version\":\"${local.engine_ver_actual}\",\"username\":\"default\",\"password\":\"${local.auth_token_effective}\",\"port\":\"${local.redis_port}\",\"primary_endpoint\":\"${local.primary_endpoint}\",\"reader_endpoint\":\"${local.reader_endpoint}\",\"subnet_group\":\"${aws_elasticache_subnet_group.cache.name}\",\"subnets\":\"${local.subnets_csv}\",\"security_group_id\":\"${aws_security_group.cache.id}\"}"
}

resource "aws_secretsmanager_secret" "cache" {
  name = "${local.cache_identifier}-secret"
  tags = local.tags_common
}

resource "aws_secretsmanager_secret_version" "cache" {
  secret_id     = aws_secretsmanager_secret.cache.id
  secret_string = local.secret_payload
}
