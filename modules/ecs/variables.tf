# variables.tf
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

variable "alb_state_key" {
  type = string
}

variable "service_count" {
  type    = number
  default = 1
}

variable "container_image" {
  type    = string
  default = ""
}

variable "container_cpu" {
  type    = number
  default = 1024
}

variable "container_memory" {
  type    = number
  default = 2048
}

variable "ephemeral_storage_gib" {
  type    = number
  default = 25
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "ecr_repo_name_override" {
  type    = string
  default = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}
