# Simple: WAF (CDN) Terragrunt config

# CDN first
dependencies {
  paths = ["${local.rel_up}/cdn"]
}

locals {
  # Where we are
  this_dir        = get_terragrunt_dir()
  parent_dir      = dirname(local.this_dir)            # .../waf
  grandparent_dir = dirname(local.parent_dir)          # .../<intake_id> or .../decommission
  is_decommission = basename(local.grandparent_dir) == "decommission"

  # Intake dir/id
  intake_dir = local.is_decommission ? dirname(local.grandparent_dir) : local.grandparent_dir
  intake_id  = basename(local.intake_dir)

  # Inputs
  cfg = jsondecode(file(find_in_parent_folders("inputs.json")))

  # Component (nested)
  component        = basename(local.this_dir)          # "cdn_waf"
  component_parent = basename(local.parent_dir)        # "waf"
  component_path   = "${local.component_parent}/${local.component}"  # "waf/cdn_waf"

  # Repo layout agnostic
  infra_root  = dirname(dirname(dirname(local.intake_dir)))     # .../<infra_root>/live/sandbox/<intake_id>/
  modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules") # supports modules/, modules/v1, modules/v2

  # Region / env / req
  region = coalesce(try(local.cfg.aws_region, ""), get_env("AWS_REGION", ""), get_env("AWS_DEFAULT_REGION", ""), "us-east-1")
  env    = try(local.cfg.environment, "SBX")
  req    = try(local.cfg.request_id, local.intake_id)

  # Find module block (flat or nested under "waf")
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    local.cfg.modules.waf[local.component],
    local.cfg.modules["waf"][local.component],
    {}
  )

  # Uniform Name: sbx_intake_id_001-cdn_waf-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # Paths
  state_prefix = "wbd/sandbox/${local.intake_id}"
  rel_up       = local.is_decommission ? "../../.." : "../.."   # to intake root from waf/cdn_waf
}

terraform {
  # Dynamic module source (wrapper-friendly + versioned modules)
  source = "${local.infra_root}/${local.modules_dir}/${local.component_path}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"
    key     = "${local.state_prefix}/${local.component_path}/terraform.tfstate"
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
  enabled    = try(local.mod.enabled, false)

  # Name/ids
  name       = local.name_std
  request_id = try(local.cfg.request_id, "")
  intake_id  = local.intake_id

  # Tags
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.name_std
      ServiceName = "WAF"
      Service     = "WAF_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )

  # Module specifics
  remote_state_bucket = "wbd-tf-state-sandbox"
  remote_state_region = try(local.cfg.state.region, "us-east-1")
  log_to_cloudwatch   = true
  log_retention_days  = try(local.mod.log_retention_days, 30)
}

# File: terragrunt.hcl (waf/cdn_waf)
