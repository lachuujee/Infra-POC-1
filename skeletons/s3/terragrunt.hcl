# Simple: S3 Terragrunt config (modules/s3, old working pattern)

locals {
  # Where this terragrunt.hcl lives
  this_dir   = get_terragrunt_dir()
  parent_dir = dirname(local.this_dir)

  # Intake folder: live/sandbox/intake_id_001
  intake_dir = parent_dir
  intake_id  = basename(local.intake_dir)

  # Load inputs.json from intake root
  cfg = jsondecode(file("${local.intake_dir}/inputs.json"))

  # Component name ("s3")
  component = basename(local.this_dir)

  # Repo root: …/<repo_root>
  infra_root = get_repo_root()

  # Region: inputs.json → env → default
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )

  # Env / request id
  env = try(local.cfg.environment, "sbx")
  req = try(local.cfg.request_id, local.intake_id)

  # Module block from inputs.json (supports "s3", "AWS s3", "S3")
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    {}
  )

  # Enable flag (default false so nothing runs if not set)
  enabled = try(local.mod.enabled, false)

  # Name from inputs.json or derived
  mod_name = try(local.mod.name, "${local.intake_id}-${local.component}")

  # Canonical name for resources / tags
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # Bucket name override: clean + DNS safe
  bucket_name_override_raw = try(local.mod.name, local.name_std)
  bucket_name_override     = replace(lower(bucket_name_override_raw), "_", "-")

  # State prefix
  state_prefix = "wbd/sandbox/${local.intake_id}"
}

terraform {
  # EXACTLY like your old working version – local path under repo root
  source = "${local.infra_root}/modules/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"  # change only the bucket name if needed
    key     = "${local.state_prefix}/${local.component}/terraform.tfstate"
    region  = local.region
    encrypt = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"

  # Assume destination role from inputs.json (iam_role)
  assume_role {
    role_arn     = "${try(local.cfg.iam_role, "")}"
    session_name = "SandboxProvisioningSession"
  }
}
EOF
}

inputs = {
  # module expects region
  region      = local.region

  # from inputs.json / locals
  enabled     = local.enabled
  name        = local.name_std
  request_id  = try(local.cfg.request_id, "")
  bucket_name_override = local.bucket_name_override

  # defaults
  versioning    = true
  block_public  = true
  force_destroy = false
  kms_key_id    = null   # AWS-managed KMS

  # cost/reporting tags
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      RequestID   = try(local.cfg.request_id, "")
      Environment = local.env
      IntakeID    = local.intake_id
      ServiceName = upper(local.component)                       # S3
      Service     = "${upper(local.component)}_${local.intake_id}" # S3_intake_id_001
      BU_Unit     = try(local.cfg.bu_unit, "WBD_sandbox")
    }
  )
}
