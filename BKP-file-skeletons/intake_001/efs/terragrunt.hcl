# terragrunt.hcl
dependencies {
  paths = ["../vpc"]
}

locals {
  cfg       = jsondecode(file(find_in_parent_folders("inputs.json")))
  region    = coalesce(try(local.cfg.aws_region, ""), get_env("AWS_REGION", ""), get_env("AWS_DEFAULT_REGION", ""), "us-east-1")
  component = basename(get_terragrunt_dir())
  intake_id = basename(dirname(get_terragrunt_dir()))
  env       = try(local.cfg.environment, "SBX")
  req       = try(local.cfg.request_id, local.intake_id)
  base      = "${local.env}_${local.req}"
  name      = try(local.cfg.modules[local.component].name, "${local.base}_efs")

  common_tags = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.name
      ServiceName = "efs"
      Service     = "efs_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )
}

terraform {
  source = "${get_repo_root()}/modules/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"
    key     = "wbd/sandbox/${local.intake_id}/${local.component}/terraform.tfstate"
    region  = try(local.cfg.state.region, "us-east-1")
    encrypt = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"
}
EOF
}

inputs = {
  region               = local.region
  env                  = local.env
  name                 = local.name
  request_id           = local.req
  common_tags          = local.common_tags

  remote_state_bucket  = "wbd-tf-state-sandbox"
  remote_state_region  = try(local.cfg.state.region, "us-east-1")
  vpc_state_key        = "wbd/sandbox/${local.intake_id}/vpc/terraform.tfstate"

  availability_zone    = try(local.cfg.modules[local.component].availability_zone, "us-east-1a")
  subnet_id            = try(local.cfg.modules[local.component].subnet_id, "")
  allowed_cidr_blocks  = try(local.cfg.modules[local.component].allowed_cidr_blocks, [])
}
