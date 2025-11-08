# Ensure VPC applies first
dependencies {
  paths = ["../vpc"]
}

locals {
  cfg    = jsondecode(file(find_in_parent_folders("inputs.json")))
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )

  intake_id        = basename(dirname(get_terragrunt_dir()))
  module_component = "lb"
  component_key    = "lb"

  sandbox = try(local.cfg.sandbox_name, "sbx")
  env     = try(local.cfg.environment, "SBX")
  req     = try(local.cfg.request_id, local.intake_id)
  base    = "${local.env}_${local.req}"
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

  # enable flags and names
  alb_enabled = try(local.cfg.modules.lb_alb.enabled, false)
  nlb_enabled = try(local.cfg.modules.lb_nlb.enabled, false)
  alb_name    = try(local.cfg.modules.lb_alb.name, "")
  nlb_name    = try(local.cfg.modules.lb_nlb.name, "")

  # exposure (default private)
  public = coalesce(
    try(local.cfg.modules.lb_alb.public, null),
    try(local.cfg.modules.lb_nlb.public, null),
    false
  )

  # VPC state pointers
  remote_state_bucket = try(local.cfg.state.bucket, "wbd-tf-state-sandbox")
  remote_state_region = local.region
  vpc_state_key       = "wbd/sandbox/${local.intake_id}/vpc/terraform.tfstate"

  # listeners / TGs
  listener_port = 8090
  tg_port       = 8090
  tg_protocol   = "TCP"
  target_type   = "ip"

  # tags (kept in Terragrunt, same as earlier pattern)
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.base
      ServiceName = "LB"
      Service     = "LB_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )

  # Note: do NOT set alb_ingress_rules here. Edit variables.tf default if needed.
}
