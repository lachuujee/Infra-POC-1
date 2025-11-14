# Simple: CDN Terragrunt config

# WAF first (attach WebACL when CDN applies)
dependencies {
  paths = ["${local.rel_up}/waf/cdn_waf"]
}

locals {
  # Where we are (active or /decommission)
  this_dir        = get_terragrunt_dir()
  parent_dir      = dirname(local.this_dir)
  is_decommission = basename(local.parent_dir) == "decommission"

  # Intake dir/id
  intake_dir = local.is_decommission ? dirname(local.parent_dir) : local.parent_dir
  intake_id  = basename(local.intake_dir)

  # Inputs
  cfg = jsondecode(file(find_in_parent_folders("inputs.json")))

  # Component
  component = basename(local.this_dir)  # "cdn"

  # Wrapper-agnostic + versioned modules
  # .../<infra_root>/live/sandbox/<intake_id>/...
  infra_root  = dirname(dirname(dirname(local.intake_dir)))
  modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules")  # modules or modules/v1

  # Region / env / req
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )
  env = try(local.cfg.environment, "SBX")
  req = try(local.cfg.request_id, local.intake_id)

  # Module block tolerant to labels ("cdn", "AWS cdn", "CDN")
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    {}
  )

  # Uniform Name: sbx_intake_id_001-cdn-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # CDN buckets (S3 requires lowercase + hyphens)
  bucket_name      = "${replace(lower(local.name_std), "_", "-")}-s3"
  logs_bucket_name = "${local.bucket_name}-logs"

  # Paths
  state_prefix = "wbd/sandbox/${local.intake_id}"
  rel_up       = local.is_decommission ? "../.." : ".."
}

terraform {
  # Dynamic source (wrapper-friendly + versioned modules)
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
  enabled = try(local.mod.enabled, false)

  # Names / ids
  name       = local.name_std
  request_id = local.req

  # CDN specifics
  bucket_name      = local.bucket_name
  logs_bucket_name = local.logs_bucket_name
  origin_path      = try(local.mod.origin_path, "/frontend")

  # Tags
  common_tags = merge(
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

  # --- State pointers at the very bottom (dependency state) ---
  remote_state_bucket = "wbd-tf-state-sandbox"
  remote_state_region = try(local.cfg.state.region, "us-east-1")
  waf_state_key       = "${local.state_prefix}/waf/cdn_waf/terraform.tfstate"
}

# File: terragrunt.hcl (cdn)
