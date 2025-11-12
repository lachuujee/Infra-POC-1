# Simple: VPC Terragrunt config

# (No explicit dependencies for VPC)

locals {
  # Where we are
  this_dir   = get_terragrunt_dir()
  parent_dir = dirname(local.this_dir)

  # Load inputs from the intake root
  cfg = jsondecode(file(find_in_parent_folders("inputs.json")))

  # Identify component and intake dir/id
  component  = basename(local.this_dir)                                  # "vpc"
  intake_dir = parent_dir
  intake_id  = basename(local.intake_dir)

  # Derive <infra_root> from inputs.json path so this works in personal & office repos
  # .../<infra_root>/live/sandbox/<intake_id>/...
  infra_root = dirname(dirname(dirname(local.intake_dir)))

  # Region / env / req
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )
  env = try(local.cfg.environment, "SBX")
  req = try(local.cfg.request_id, local.intake_id)

  # Resolve the module block regardless of label style ("vpc", "AWS vpc", "VPC")
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
  # Dynamic source path (works if modules/ is at repo-root or inside Sandbox-Infra/)
  source = "${local.infra_root}/modules/${local.component}"
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
