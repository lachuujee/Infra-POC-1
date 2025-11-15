variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type = string
}

variable "name" {
  type = string
}

variable "request_id" {
  type    = string
  default = ""
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

variable "cache_engine" {
  type    = string
  default = "redis_oss"
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "parameter_group_name" {
  type    = string
  default = "default.redis7"
}

variable "port" {
  type    = number
  default = 6379
}

variable "subnet_ids_override" {
  type    = list(string)
  default = []
}

variable "api_subnet_ids" {
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

variable "auto_minor_version_upgrade" {
  type    = bool
  default = true
}

variable "multi_az_enabled" {
  type    = bool
  default = false
}

variable "replicas_per_node_group" {
  type    = number
  default = 0
}

variable "transit_encryption_enabled" {
  type    = bool
  default = true
}

variable "at_rest_encryption_enabled" {
  type    = bool
  default = true
}

variable "maintenance_window" {
  type    = string
  default = ""
}

variable "snapshot_window" {
  type    = string
  default = ""
}

variable "snapshot_retention_limit" {
  type    = number
  default = 0
}
