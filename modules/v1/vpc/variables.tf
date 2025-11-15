variable "sandbox_name" {
  type        = string
  description = "Base name, e.g. sbx_intake_id_001"
}

variable "name_prefix_override" {
  type        = string
  default     = null
  description = "Optional override for name prefix. If null, sandbox_name is used."
}

variable "ipam_pool_id" {
  type        = string
  default     = null
  description = "If set, VPC will be allocated from this IPAM pool."
}

variable "vpc_netmask_length" {
  type        = number
  default     = 16
  description = "Netmask length when allocating from IPAM (only used if ipam_pool_id is set)."
}

variable "cidr_block" {
  type        = string
  default     = null
  description = "If set (and ipam_pool_id not set), VPC will use this CIDR."
}

variable "azs" {
  type        = list(string)
  default     = null
  description = "Optional AZs (need at least 2 if provided). If null, first two AZs in region are used."
}

variable "flow_logs_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch retention for VPC flow logs."
}

variable "tags_extra" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged into all resources."
}

locals {
  name_prefix = var.name_prefix_override != null ? var.name_prefix_override : var.sandbox_name

  common_tags = merge(
    { Name = local.name_prefix },
    var.tags_extra
  )
}
