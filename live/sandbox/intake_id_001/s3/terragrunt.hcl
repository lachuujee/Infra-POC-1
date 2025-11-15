# -----------------------
# S3 Terragrunt component
# -----------------------

locals {
  # Where we are
  this_dir    = get_terragrunt_dir()
  parent_dir  = dirname(local.this_dir)

  # Intake dir / id
  intake_dir  = dirname(local.parent_dir)
  intake_id   = basename(local.intake_dir)

  # Load inputs (from live/<intake_id>/inputs.json)
  cfg         = jsondecode(file(find_in_parent_folders("inputs.json")))

  # Component name (folder name, e.g., "s3")
  component   = basename(local.this_dir)

  # Repo root and modules dir (env override: MODULES_DIR; default modules/v1)
  infra_root  = dirname(dirname(local.intake_dir))
  modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules/v1")

  # Region
  region      = coalesce(
                  try(local.cfg.aws_region, null),
                  get_env("AWS_REGION", null),
                  get_env("AWS_DEFAULT_REGION", null),
                  "us-east-1"
                )

  # Uniform name pieces (optional)
  env         = try(local.cfg.environment, "SBX")
  req         = try(local.cfg.request_id, local.intake_id)

  # State key prefix per intake
  state_prefix = "wbd/sandbox/${local.intake_id}"
}

terraform {
  # Dynamic module source (wrapper-friendly + versioned modules)
  source = "${local.infra_root}/${local.modules_dir}/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox-poc"
    key    = "${local.state_prefix}/${local.component}/terraform.tfstate"
    region = try(local.cfg.state.region, local.region)
    encrypt = true
  }
}

# Force Terraform to assume the deploy role for ALL AWS calls (incl. S3 state)
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

# Pass variables to the underlying module (kept lean; module will read what it needs)
inputs = {
  enabled            = try(local.cfg.mod.enabled, true)
  region             = local.region
  name               = try(local.cfg.name, local.component)
  request_id         = local.req
  tags               = try(local.cfg.tags, {})
  bucket_name_override = try(local.cfg.bucket_name_override, null)
}
