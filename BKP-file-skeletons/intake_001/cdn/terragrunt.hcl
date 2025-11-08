dependencies {
  paths = ["../vpc"]
}

locals {
  cfg       = jsondecode(file(find_in_parent_folders("inputs.json")))
  region    = coalesce(try(local.cfg.aws_region, ""), get_env("AWS_REGION", ""), get_env("AWS_DEFAULT_REGION", ""), "us-east-1")
  component = basename(get_terragrunt_dir())
  intake_id = basename(dirname(get_terragrunt_dir()))
  env       = try(local.cfg.environment, "SBX")
  req       = try(local.cfg.request_id, local.intake_id)
  base      = "${local.env}_${local.req}"

  # CDN name stays with underscores (for tags)
  name = try(local.cfg.modules[local.component].name, "${local.base}_cdn")

  # S3 requires hyphens — two-liner
  bucket_name      = lower("${replace(local.name, "_", "-")}-s3")
  logs_bucket_name = "${local.bucket_name}-logs"

  common_tags = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.name
      ServiceName = "CDN"
      Service     = "CDN_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )
}

terraform {
  source = "${get_repo_root()}/modules/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"
    key     = "wbd/sandbox/${local.intake_id}/${local.component}/terraform.tfstate"
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
  enabled          = try(local.cfg.modules[local.component].enabled, true)
  name             = local.name
  request_id       = local.req

  bucket_name      = local.bucket_name
  logs_bucket_name = local.logs_bucket_name
  common_tags      = local.common_tags

  # keep module defaults in variables.tf; override only if needed
  origin_path = try(local.cfg.modules[local.component].origin_path, "/frontend")
}
