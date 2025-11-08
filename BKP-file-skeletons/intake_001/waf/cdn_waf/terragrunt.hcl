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
  module_component = "waf/cdn_waf"
  component_key    = "waf/cdn_waf"

  sandbox = try(local.cfg.sandbox_name, "sbx")

  base    = try(local.cfg.sandbox_name, local.intake_id)
  base_k  = lower(replace(local.base, "_", "-"))
  name    = try(local.cfg.modules.cdn.name, "${local.base}_cdn")
}

dependencies {
  paths = ["../../cdn"]
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
  enabled     = try(local.cfg.modules.waf.cdn_waf.enabled, true)
  name        = local.name
  request_id  = try(local.cfg.request_id, "")
  intake_id   = local.intake_id

  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      RequestID   = try(local.cfg.request_id, "")
      Requester   = try(local.cfg.requester, "")
      Environment = try(local.cfg.environment, "sandbox")
      ServiceName = "WAF"
      Service     = "WAF_${local.intake_id}"
      BU_Unit     = try(local.cfg.bu_unit, "WBD_sandbox")
      Name        = local.name
    }
  )

  remote_state_bucket = try(local.cfg.state.bucket, "wbd-tf-state-sandbox")
  remote_state_region = try(local.cfg.state.region, "us-east-1")

  log_to_cloudwatch  = true
  log_retention_days = try(local.cfg.modules.waf.cdn_waf.log_retention_days, 30)
}
