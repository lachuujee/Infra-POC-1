# Simple: LB Terragrunt config

# VPC first
dependencies {
  paths = ["${local.rel_up}/vpc"]
}

locals {
  # Where we are (works in active and /decommission)
  this_dir        = get_terragrunt_dir()
  parent_dir      = dirname(local.this_dir)
  is_decommission = basename(local.parent_dir) == "decommission"

  # Intake dir/id
  intake_dir = local.is_decommission ? dirname(local.parent_dir) : local.parent_dir
  intake_id  = basename(local.intake_dir)

  # Inputs
  cfg = jsondecode(file(find_in_parent_folders("inputs.json")))

  # Component
  component = basename(local.this_dir)  # "lb"

  # Repo layout + versioned modules support
  infra_root  = dirname(dirname(dirname(local.intake_dir)))
  modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules")  # e.g., modules or modules/v1

  # Region / env / req
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )
  env = try(local.cfg.environment, "SBX")
  req = try(local.cfg.request_id, local.intake_id)

  # Uniform Name: sbx_intake_id_001-lb-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # Convenience module blocks
  mod_alb = try(local.cfg.modules.lb_alb, {})
  mod_nlb = try(local.cfg.modules.lb_nlb, {})

  # State prefix (stable)
  state_prefix = "wbd/sandbox/${local.intake_id}"
  rel_up       = local.is_decommission ? "../.." : ".."
}

terraform {
  # Dynamic source path (wrapper-friendly + versioned modules)
  source = "${local.infra_root}/${local.modules_dir}/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"
    key     = "${local.state_prefix}/${local.component}/terraform.tfstate"
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
  # Names / ids
  env        = local.env
  region     = local.region
  request_id = local.req

  # ALB/NLB toggles and names
  alb_enabled = try(local.mod_alb.enabled, false)
  nlb_enabled = try(local.mod_nlb.enabled, false)
  alb_name    = try(local.mod_alb.name, "${local.name_std}-alb")
  nlb_name    = try(local.mod_nlb.name, "${local.name_std}-nlb")

  # Exposure / listeners
  public        = coalesce(try(local.mod_alb.public, null), try(local.mod_nlb.public, null), false)
  listener_port = try(local.mod_alb.listener_port, 8090)
  tg_port       = try(local.mod_alb.tg_port, 8090)
  tg_protocol   = try(local.mod_alb.tg_protocol, "TCP")
  target_type   = try(local.mod_alb.target_type, "ip")

  # Tags (tags_extra)
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.name_std
      ServiceName = upper(local.component)
      Service     = "${upper(local.component)}_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )

  # --- State pointers at the very bottom ---
  remote_state_bucket = "wbd-tf-state-sandbox"
  remote_state_region = try(local.cfg.state.region, "us-east-1")
  vpc_state_key       = "${local.state_prefix}/vpc/terraform.tfstate"
}

# File: terragrunt.hcl (lb)
