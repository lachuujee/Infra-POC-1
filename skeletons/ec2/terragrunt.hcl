# Simple: EC2 Terragrunt config (provision + works from /decommission too)

# Ensure VPC, IAM instance-profile, KeyPair apply first
dependencies {
  paths = ["../vpc", "../iam/instance_profile", "../keypair"]
}

locals {
  # Where we are
  this_dir        = get_terragrunt_dir()
  parent_dir      = dirname(local.this_dir)
  is_decommission = basename(local.parent_dir) == "decommission"

  # Load inputs (prefer scoped decommission file if present)
  decom_inputs_path = "${local.parent_dir}/decommission.inputs.json"
  cfg = fileexists(local.decom_inputs_path)
      ? jsondecode(file(local.decom_inputs_path))
      : jsondecode(file(find_in_parent_folders("inputs.json")))

  # Identify component and intake dir/id (works in active and /decommission)
  component  = basename(local.this_dir)                                  # "ec2"
  intake_dir = local.is_decommission ? dirname(local.parent_dir) : local.parent_dir
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

  # Resolve the module block regardless of label style ("ec2", "AWS ec2", "EC2")
  mod = try(
    local.cfg.modules[local.component],
    local.cfg.modules["AWS ${local.component}"],
    local.cfg.modules[upper(local.component)],
    {}
  )

  # Uniform Name: sbx_intake_id_001-<component>-dev
  name_base = lower(try(local.cfg.sandbox_name, "${local.env}_${local.req}"))
  name_env  = lower(local.env)
  name_std  = "${local.name_base}-${local.component}-${local.name_env}"

  # Relative up for dependency paths
  rel_up = local.is_decommission ? "../.." : ".."

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
  # If you prefer using run-all destroy in /decommission, keep this true/ignored by destroy.
  # If you want "apply" to decommission, set enabled = local.is_decommission ? false : try(local.mod.enabled, false)
  enabled = try(local.mod.enabled, false)

  # Strict, uniform resource name
  name = local.name_std

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

  # --- EC2 module inputs (unchanged defaults) ---
  instance_count    = try(local.mod.instance_count, 1)
  instance_type     = try(local.mod.instance_type, "t2.micro")
  ami_id            = try(local.mod.ami_id, null)
  ami_ssm_parameter = try(local.mod.ami_ssm_parameter, "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2")

  subnet_role_keys  = ["api-a", "api-b"]

  # Remote-state locations the EC2 module reads
  remote_state_bucket = "wbd-tf-state-sandbox"
  remote_state_region = try(local.cfg.state.region, "us-east-1")
  vpc_state_key       = "${local.state_prefix}/vpc/terraform.tfstate"
  iam_state_key       = "${local.state_prefix}/iam/instance_profile/terraform.tfstate"
  keypair_state_key   = "${local.state_prefix}/keypair/terraform.tfstate"
}

# File: terragrunt.hcl (ec2)
