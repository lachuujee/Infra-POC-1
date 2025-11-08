# variable.f
variable "name" {
  type = string
}

variable "request_id" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
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

variable "base_rpus" {
  type    = number
  default = 4
}

variable "max_rpus" {
  type    = number
  default = 16
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}

variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
}
