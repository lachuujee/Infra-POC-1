locals {
  cfg        = jsondecode(file(find_in_parent_folders("inputs.json")))
  # Region: inputs.json -> env -> default
  region     = coalesce(
                 try(local.cfg.aws_region, ""),
                 get_env("AWS_REGION", ""),
                 get_env("AWS_DEFAULT_REGION", ""),
                 "us-east-1"
               )
  component  = basename(get_terragrunt_dir())          # "s3"
  intake_id  = basename(dirname(get_terragrunt_dir())) # "intake_001"
}

terraform {
  source = "${get_repo_root()}/modules/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"
    key     = "wbd/sandbox/${local.intake_id}/${local.component}/terraform.tfstate"
    region  = local.region
    encrypt = true
    # no DynamoDB lock
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
  # module expects region
  region               = local.region

  # from inputs.json
  enabled              = try(local.cfg.modules[local.component].enabled, true)
  name                 = local.cfg.modules[local.component].name
  request_id           = local.cfg.request_id
  bucket_name_override = local.cfg.modules[local.component].name

  # defaults
  versioning    = true
  block_public  = true
  force_destroy = false
  kms_key_id    = null   # AWS-managed KMS

  # cost/reporting tags
  tags_extra = {
    RequestID    = local.cfg.request_id
    Environment  = try(local.cfg.environment, "sbx")
    IntakeID     = local.intake_id
    ServiceName  = upper(local.component)                  # S3
    Service      = "${upper(local.component)}_${local.intake_id}"  # S3_intake_001
    BU_Unit      = try(local.cfg.bu_unit, "WBD_sandbox")
  }
}
