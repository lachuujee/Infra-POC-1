locals {
  cfg    = jsondecode(file(find_in_parent_folders("inputs.json")))
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )

  # USE THE DIRECTORY THAT CONTAINS inputs.json (the real intake folder)
  intake_id        = basename(dirname(find_in_parent_folders("inputs.json")))
  module_component = "IAM/Instance_Profile"
  component_key    = "iam/instance_profile"

  sandbox = try(local.cfg.sandbox_name, "sbx")

  base    = try(local.cfg.sandbox_name, local.intake_id)
  base_k  = lower(replace(local.base, "_", "-"))
  role    = "${local.base_k}-ec2-instance-role"
  profile = "${local.role}-profile"
}

terraform {
  source = "${get_repo_root()}/modules/${local.module_component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = try(local.cfg.state.bucket, "wbd-tf-state-sandbox")
    key     = "wbd/sandbox/${local.intake_id}/${local.component_key}/terraform.tfstate"
    region  = try(local.cfg.state.region, "us-east-1")
    encrypt = true
  }
}

inputs = {
  enabled               = try(local.cfg.modules.iam.instance_profile.enabled, true)
  role_name             = try(local.cfg.modules.iam.instance_profile.role_name, local.role)
  instance_profile_name = try(local.cfg.modules.iam.instance_profile.instance_profile_name, local.profile)
  path                  = try(local.cfg.modules.iam.instance_profile.path, "/")

  managed_policy_arns = try(local.cfg.modules.iam.instance_profile.managed_policy_arns, [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ])

  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      RequestID   = try(local.cfg.request_id, "")
      Requester   = try(local.cfg.requester, "")
      Environment = try(local.cfg.environment, "sandbox")
      ServiceName = "IAM"
      Service     = "IAM_${local.intake_id}"
      BU_Unit     = try(local.cfg.bu_unit, "WBD_sandbox")
    }
  )
}
