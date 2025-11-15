data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    region = var.remote_state_region
    key    = var.vpc_state_key
  }
}

resource "aws_security_group" "efs" {
  name        = var.name
  description = "Security group for EFS"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  tags        = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.efs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nfs_cidr" {
  for_each          = { for cidr in var.allowed_cidr_blocks : cidr => cidr }
  security_group_id = aws_security_group.efs.id
  cidr_ipv4         = each.value
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
}

resource "aws_efs_file_system" "this" {
  encrypted              = true
  availability_zone_name = var.availability_zone
  performance_mode       = "generalPurpose"
  throughput_mode        = "elastic"
  kms_key_id             = length(var.kms_key_id) > 0 ? var.kms_key_id : null
  tags                   = var.common_tags
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_mount_target" "mt" {
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = data.terraform_remote_state.vpc.outputs.private_subnet_ids_by_role["api-a"]
  security_groups = [aws_security_group.efs.id]
}
