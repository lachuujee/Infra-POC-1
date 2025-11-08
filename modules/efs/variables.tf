variable "region" {
  type = string
}

variable "env" {
  type = string
}

variable "name" {
  type = string
}

variable "request_id" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "remote_state_bucket" {
  type = string
}

variable "remote_state_region" {
  type = string
}

variable "vpc_state_key" {
  type = string
}

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "subnet_id" {
  type = string
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}

variable "kms_key_id" {
  type    = string
  default = ""
}
