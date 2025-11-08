locals {
  cfg        = jsondecode(file(find_in_parent_folders("inputs.json")))
  # Region: inputs.json -> env -> default
  region     = coalesce(
                 try(local.cfg.aws_region, ""),
                 get_env("AWS_REGION", ""),
                 get_env("AWS_DEFAULT_REGION", ""),
                 "us-east-1"
               )
  component  = basename(get_terragrunt_dir())          # "keypair"
  intake_id  = basename(dirname(get_terragrunt_dir())) # "intake_001"

  # Name pieces (no transforms)
  env        = try(local.cfg.environment, "SBX")
  req        = try(local.cfg.request_id, local.intake_id)
  base       = "${local.env}_${local.req}"             # e.g., SBX_intake_id_001
}

# Keep ordering for run-all (KeyPair after VPC)
dependencies {
  paths = ["../vpc"]
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
  # Enable: keypair.enabled -> else ec2.enabled -> else false
  enabled            = try(local.cfg.modules[local.component].enabled,
                        try(local.cfg.modules.ec2.enabled, false))

  # Resource name (module will use this directly)
  key_name_override  = "${local.base}_keypair"  # SBX_intake_id_001_keypair

  # Tags — match S3 style; Every Tag Key starts with Capital letter
  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.base                     # SBX_intake_id_001
      ServiceName = local.base                     # same as Name
      Service     = "${local.base}_keypair"        # SBX_intake_id_001_keypair
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")  # default WBD
    }
  )
}
