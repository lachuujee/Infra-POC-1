locals {
  cfg    = jsondecode(file(find_in_parent_folders("inputs.json")))
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )

  intake_id        = basename(dirname(get_terragrunt_dir()))
  module_component = "vpc"                 # module path under /modules
  component_key    = "vpc"                 # state key folder

  sandbox = try(local.cfg.sandbox_name, "sbx")
}

terraform {
  source = "${get_repo_root()}/modules/${local.module_component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = try(local.cfg.state.bucket, "wbd-tf-state-sandbox")
    key     = "wbd/sandbox/${local.intake_id}/${local.component_key}/terraform.tfstate"
    region  = local.region
    encrypt = true
  }
}

inputs = {
  # naming
  sandbox_name = local.sandbox

  # addressing (pick one or none)
  ipam_pool_id       = try(local.cfg.modules.vpc.ipam_pool_id, null)
  vpc_netmask_length = try(local.cfg.modules.vpc.vpc_netmask_length, 16)
  cidr_block         = try(local.cfg.modules.vpc.cidr_block, null)

  # optional azs override (else module picks first two in region)
  azs = try(local.cfg.modules.vpc.azs, null)

  flow_logs_retention_days = try(local.cfg.modules.vpc.flow_logs_retention_days, 30)

  # Tags mirror IAM/S3 pattern
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      RequestID   = try(local.cfg.request_id, "")
      Requester   = try(local.cfg.requester, "")
      Environment = try(local.cfg.environment, "sandbox")
      Service     = "VPC"
    }
  )
}
