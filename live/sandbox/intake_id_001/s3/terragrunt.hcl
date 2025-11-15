# File: live/sandbox/<intake_id>/s3/terragrunt.hcl

locals {
  # Where we are (works in active and /decommission)
  this_dir        = get_terragrunt_dir()
  parent_dir      = dirname(local.this_dir)
  is_decommission = basename(local.parent_dir) == "decommission"

  # Intake dir/id (root of the intake)
  intake_dir = local.is_decommission ? dirname(local.parent_dir) : local.parent_dir
  intake_id  = basename(local.intake_dir)

  # Load inputs.json from the intake root
  cfg = jsondecode(file("${local.intake_dir}/inputs.json"))

  # Component name ("s3")
  component = basename(local.this_dir)

  # Infra root: .../<repo_root>/live/sandbox/<intake_id>/s3
  infra_root  = dirname(dirname(dirname(local.intake_dir)))
  modules_dir = get_env("MODULES_DIR", "modules") # e.g. "modules" or "modules/v1"

  # Region / env / request id
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )

  env = try(local.cfg.environment, "SBX")
  req = try(local.cfg.request_id, local.intake_id)

  # Module block from inputs.json (supports "s3", "AWS s3", "S3")
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    {}
  )

  # Dynamic enable flag (from inputs.json)
  enabled = try(local.mod.enabled, false)

  # Uniform name: sbx_intake_id_001-s3-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # State prefix for remote state
  state_prefix = "wbd/sandbox/${local.intake_id}"
}

terraform {
  # Dynamic module source (MODULES_DIR can be "modules" or "modules/v1")
  source = "${local.infra_root}/${local.modules_dir}/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox" # change if your state bucket name is different
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
  # Passed into the Terraform S3 module
  enabled     = local.enabled

  # Names
  name        = local.name_std
  request_id  = try(local.cfg.request_id, "")

  # S3-specific
  region               = local.region
  bucket_name_override = replace(lower(local.name_std), "_", "-")

  versioning    = true
  block_public  = true
  force_destroy = false
  kms_key_id    = null

  # Tags
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
