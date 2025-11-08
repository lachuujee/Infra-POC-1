variable "enabled" {
  type    = bool
  default = true
}

variable "name" {
  type = string
}

variable "request_id" {
  type = string
}

variable "port" {
  type    = number
  default = 54321
}

variable "preferred_az" {
  type    = string
  default = "us-east-1a"
}

variable "serverlessv2_min_acu" {
  type    = number
  default = 1
}

variable "serverlessv2_max_acu" {
  type    = number
  default = 8
}

variable "enabled_cloudwatch_logs_exports" {
  type    = list(string)
  default = ["postgresql"]
}

variable "remote_state_bucket" {
  type    = string
  default = null
}

variable "vpc_state_key" {
  type    = string
  default = null
}

variable "remote_state_region" {
  type    = string
  default = null
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
