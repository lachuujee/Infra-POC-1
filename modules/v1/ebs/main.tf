data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    region = var.remote_state_region
    key    = var.vpc_state_key
  }
}

resource "aws_ebs_volume" "this" {
  availability_zone = var.availability_zone
  size              = var.size_gib
  type              = var.volume_type
  iops              = contains(["gp3", "io1", "io2"], var.volume_type) ? var.iops : null
  throughput        = var.volume_type == "gp3" ? var.throughput_mibps : null
  encrypted         = true
  kms_key_id        = length(var.kms_key_id) > 0 ? var.kms_key_id : null
  tags              = var.common_tags
}
