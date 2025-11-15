# terragrunt.hcl  (module-level, e.g. live/sandbox/<intake_id>/<component>/terragrunt.hcl)

locals {
  # Where we are (supports active and /decommission)
  this_dir       = get_terragrunt_dir()
  parent_dir     = dirname(local.this_dir)
  is_decommission = basename(local.parent_dir) == "decommission"

  # Intake dir / id
  intake_dir = local.is_decommission ? dirname(local.parent_dir) : local.parent_dir
  intake_id  = basename(local.intake_dir)

  # Load inputs
  cfg = jsondecode(file(find_in_parent_folders("inputs.json")))

  # Component name (folder name)
  component = basename(local.this_dir)

  # Wrapper-agnostic + versioned modules support
  # infra_root = <repo_root>/live/sandbox/<intake_id>/
  infra_root  = dirname(dirname(local.intake_dir))
  modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules")  # e.g., "modules" or "modules/v1"

  # Region (prefer inputs, then env, then default)
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )

  # Environment / request id
  env = try(local.cfg.environment, "SBX")
  req = try(local.cfg.request_id, local.intake_id)

  # Module block from inputs.json (supports label variants)
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    {}
  )

  # Uniform name pieces
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # Remote state key prefix
  state_prefix = "wbd/sandbox/${local.intake_id}"
}

terraform {
  # Dynamic module source (wrapper-friendly + versioned)
  source = "${local.infra_root}/${local.modules_dir}/${local.component}"
}

# S3 remote state (defaults can be overridden via inputs.json)
remote_state {
  backend = "s3"
  config = {
    bucket  = try(local.cfg.state_bucket, try(local.cfg.state.bucket, "wbd-tf-state-sandbox-poc"))
    key     = "${local.state_prefix}/${local.component}/terraform.tfstate"
    region  = local.region
    encrypt = true
  }
}

# Generate a provider that can optionally assume role from inputs.json
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"
  assume_role {
    role_arn     = "${try(local.cfg.iam_role, "")}"
    session_name = "SandboxProvisioningSession"
  }
}
EOF
}

# Inputs handed to modules (trim to what your modules expect)
inputs = {
  enabled   = try(local.mod.enabled, true)
  name_base = local.name_base
  name_env  = local.name_env
  name_std  = local.name_std
  region    = local.region

  # pass through anything your module expects from inputs.json
  # e.g. tags = try(local.cfg.tags, {})
}
