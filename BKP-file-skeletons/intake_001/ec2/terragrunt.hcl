# Ensure VPC, IAM instance-profile, KeyPair apply first
dependencies {
  paths = ["../vpc", "../iam/instance_profile", "../keypair"]
}

locals {
  cfg    = jsondecode(file(find_in_parent_folders("inputs.json")))
  region = coalesce(
    try(local.cfg.aws_region, ""),
    get_env("AWS_REGION", ""),
    get_env("AWS_DEFAULT_REGION", ""),
    "us-east-1"
  )
  component = basename(get_terragrunt_dir())          # "ec2"
  intake_id = basename(dirname(get_terragrunt_dir())) # "intake_001"

  env  = try(local.cfg.environment, "SBX")
  req  = try(local.cfg.request_id, local.intake_id)
  base = "${local.env}_${local.req}"                  # e.g., SBX_intake_id_001
}

terraform {
  source = "${get_repo_root()}/modules/${local.component}"
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "wbd-tf-state-sandbox"
    key     = "wbd/sandbox/${local.intake_id}/${local.component}/terraform.tfstate"
    region  = try(local.cfg.state.region, "us-east-1")  # use bucket's region
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
  enabled = try(local.cfg.modules[local.component].enabled, false)

  name = try(local.cfg.modules[local.component].name, "${local.base}_ec2")

  tags_extra = merge(
    try(local.cfg.tags, {}),
    {
      Name        = local.base
      ServiceName = "EC2"
      Service     = "EC2_${local.intake_id}"
      Environment = local.env
      RequestID   = local.req
      Requester   = try(local.cfg.requester, "")
      BU_Unit     = try(local.cfg.bu_unit, "WBD")
    }
  )

  instance_count    = try(local.cfg.modules.ec2.instance_count, 1)
  instance_type     = try(local.cfg.modules.ec2.instance_type, "t2.micro")
  ami_id            = try(local.cfg.modules.ec2.ami_id, null)
  ami_ssm_parameter = try(local.cfg.modules.ec2.ami_ssm_parameter, "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2")

  subnet_role_keys  = ["api-a", "api-b"]

  # remote-state locations the EC2 module reads
  remote_state_bucket = "wbd-tf-state-sandbox"
  remote_state_region = try(local.cfg.state.region, "us-east-1")  # use bucket's region
  vpc_state_key       = "wbd/sandbox/${local.intake_id}/vpc/terraform.tfstate"
  iam_state_key       = "wbd/sandbox/${local.intake_id}/iam/instance_profile/terraform.tfstate"
  keypair_state_key   = "wbd/sandbox/${local.intake_id}/keypair/terraform.tfstate"
}
