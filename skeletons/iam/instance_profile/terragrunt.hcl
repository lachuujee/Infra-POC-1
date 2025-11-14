# Simple: IAM Instance-Profile Terragrunt config

# (No explicit dependencies for IAM/Instance_Profile)

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

  # Component (nested path)
  component_parent = "iam"
  component        = "instance_profile"
  component_path   = "${local.component_parent}/${local.component}"

  # Wrapper-agnostic + versioned modules
  # .../<infra_root>/live/sandbox/<intake_id>/...
  infra_root  = dirname(dirname(dirname(local.intake_dir)))
  modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules")  # modules or modules/v1

  # Region / env / req
  region = coalesce(try(local.cfg.aws_region, ""),
                    get_env("AWS_REGION", ""),
                    get_env("AWS_DEFAULT_REGION", ""),
                    "us-east-1")
  env = try(local.cfg.environment, "SBX")
  req = try(local.cfg.request_id, local.intake_id)

  # Module block (nested under iam.instance_profile)
  mod = try(local.cfg.modules.iam.instance_profile, {})

  # Uniform Name: sbx_intake_id_001-instance_profile-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # Role/profile names (IAM prefers hyphens/lower)
  name_k   = replace(lower(local.name_std), "_", "-")
  role     = try(local.mod.role_name,             "${local.name_k}-ec2-instance-role")
  profile  = try(local.mod.instance_profile_name, "${local.role}-profile")

  # State prefix
  state_prefix = "wbd/sandbox/${local.intake_id}"
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
  enabled               = try(local.mod.enabled, false)

  role_name             = local.role
  instance_profile_name = local.profile
  path                  = try(local.mod.path, "/")

  managed_policy_arns = try(local.mod.managed_policy_arns, [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ])

  # Tags (uniform)
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.name_std
      ServiceName = "IAM"
      Service     = "IAM_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )

  # --- State pointers at the very bottom (none required beyond own state) ---
  remote_state_bucket = "wbd-tf-state-sandbox"
  remote_state_region = try(local.cfg.state.region, "us-east-1")
}

# File: terragrunt.hcl (iam/instance_profile)
