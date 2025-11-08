variable "enabled" {
  type    = bool
  default = true
}

variable "role_name" {
  type    = string
  default = "ec2-role"
}

variable "instance_profile_name" {
  type    = string
  default = "ec2-role-profile"
}

variable "path" {
  type    = string
  default = "/"
}

variable "managed_policy_arns" {
  type    = list(string)
  default = [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ]
}

variable "tags_extra" {
  type    = map(string)
  default = {}
}

locals {
  create = var.enabled ? 1 : 0
  tags   = var.tags_extra
}
