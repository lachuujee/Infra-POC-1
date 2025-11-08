variable "enabled" {
  type        = bool
  default     = false
  description = "Create EC2 resources."
}

variable "name" {
  type        = string
  default     = "ec2"
  description = "Base name for EC2 and the SG."
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of instances."
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 type."
}

variable "ami_id" {
  type        = string
  default     = null
  description = "If null, use AMI from SSM parameter."
}

variable "ami_ssm_parameter" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
  description = "SSM parameter for latest Amazon Linux."
}

variable "tags_extra" {
  type        = map(string)
  default     = {}
  description = "Extra tags."
}

variable "remote_state_bucket" {
  type        = string
  default     = "wbd-tf-state-sandbox"
  description = "S3 bucket for tfstate."
}

variable "remote_state_region" {
  type        = string
  default     = "us-east-1"
  description = "Region of the tfstate bucket."
}

variable "vpc_state_key" {
  type        = string
  default     = "wbd/sandbox/vpc/terraform.tfstate"
  description = "Key for the VPC state."
}

variable "iam_state_key" {
  type        = string
  default     = "wbd/sandbox/iam/instance_profile/terraform.tfstate"
  description = "Key for the IAM instance-profile state."
}

variable "keypair_state_key" {
  type        = string
  default     = "wbd/sandbox/keypair/terraform.tfstate"
  description = "Key for the KeyPair state."
}

variable "subnet_role_keys" {
  type        = list(string)
  default     = ["api-a", "api-b"]
  description = "Preferred subnet role keys."
}
