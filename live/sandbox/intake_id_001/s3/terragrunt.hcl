# File: live/sandbox/<intake_id_001>/s3/terragrunt.hcl

locals {
  # Where we are (works in active and /decommission)
  this_dir        = get_terragrunt_dir()
  parent_dir      = dirname(local.this_dir)
  is_decommission = basename(local.parent_dir) == "decommission"

  # Intake dir/id (root of the intake)
  intake_dir = local.is_decommission ? dirname(local.parent_dir) : local.parent_dir
  intake_id  = basename(local.intake_dir)

  # Load inputs.json from intake root
  cfg = jsondecode(file("${local.intake_dir}/inputs.json"))

  # Component name ("s3")
  component = basename(local.this_dir)

  # Repo root: .../<repo_root>/live/sandbox/<intake_id>/s3
  infra_root  = dirname(dirname(dirname(local.intake_dir)))

  # HARD-CODED modules dir to avoid bad env values
  modules_dir = "modules/v1"   # or "modules" if that’s your structure

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

  # State prefix
  state_prefix = "wbd/sandbox/${local.intake_id}"
}

terraform {
  # Pure local path: <repo_root>/modules/v1/s3
  source = "${local.infra_root}/${local.modules_dir}/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox-mayur"  # your state bucket
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

  assume_role {
    role_arn     = "${try(local.cfg.iam_role, "")}"
    session_name = "SandboxProvisioningSession"
  }
}
EOF
}

inputs = {
  # Enabled from inputs.json
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
