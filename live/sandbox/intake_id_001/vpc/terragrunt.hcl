# Simple: VPC Terragrunt config

# (No explicit dependencies for VPC)

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
  component = basename(local.this_dir)  # "vpc"

  # Repo layout + versioned modules support
  # .../<infra_root>/live/sandbox/<intake_id>/...
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

  # Resolve module block regardless of label style ("vpc", "AWS vpc", "VPC")
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    {}
  )

  # Uniform Name: sbx_intake_id_001-vpc-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # State prefix (stable)
  state_prefix = "wbd/sandbox/${local.intake_id}"
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
  # Enabled comes from inputs.json
  enabled = try(local.mod.enabled, false)

  # Strict, uniform resource name
  name = local.name_std

  # Addressing (pick one / or none)
  ipam_pool_id       = try(local.mod.ipam_pool_id, null)
  vpc_netmask_length = try(local.mod.vpc_netmask_length, 16)
  cidr_block         = try(local.mod.cidr_block, null)

  # Optional AZs override (else module picks first two in region)
  azs = try(local.mod.azs, null)

  flow_logs_retention_days = try(local.mod.flow_logs_retention_days, 30)

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
}

# File: terragrunt.hcl (vpc)
