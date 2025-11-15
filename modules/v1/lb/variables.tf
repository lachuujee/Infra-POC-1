# Base naming
variable "sandbox_name" {
  type        = string
  description = "Base name, e.g. sbx_intake_id_001"
}

variable "name_prefix_override" {
  type        = string
  default     = null
  description = "Optional override for name prefix. If null, sandbox_name is used."
}

# Extra tags (merged by Terragrunt)
variable "tags_extra" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged into all resources."
}

# Exposure and enable flags
variable "public" {
  type        = bool
  default     = false
  description = "When true, internet-facing; default false = internal."
}

variable "alb_enabled" {
  type        = bool
  default     = false
  description = "Create ALB when true."
}

variable "nlb_enabled" {
  type        = bool
  default     = false
  description = "Create NLB when true."
}

# LB names
variable "alb_name" {
  type        = string
  default     = ""
  description = "ALB name."
}

variable "nlb_name" {
  type        = string
  default     = ""
  description = "NLB name."
}

# VPC state pointers
variable "remote_state_bucket" {
  type        = string
  description = "S3 bucket for VPC remote state."
}

variable "remote_state_region" {
  type        = string
  description = "Region for VPC remote state bucket."
}

variable "vpc_state_key" {
  type        = string
  description = "Object key for VPC remote state."
}

# ALB ingress rules (edit here to add ports/CIDRs)
variable "alb_ingress_rules" {
  type = list(object({
    port  = number
    cidrs = list(string)
  }))
  default = [
    { port = 443,  cidrs = ["0.0.0.0/0"] }
    # Example additions (uncomment and edit as needed):
    # { port = 8090, cidrs = ["10.0.0.0/8"] },
    # { port = 8443, cidrs = ["172.16.10.0/24", "203.0.113.0/24"] }
  ]
  description = "ALB ingress rules as a list of {port, cidrs}."
}

# Listener and target group settings
variable "listener_port" {
  type        = number
  default     = 8090
  description = "Listener port."
}

variable "tg_port" {
  type        = number
  default     = 8090
  description = "Target group port."
}

variable "tg_protocol" {
  type        = string
  default     = "TCP"
  description = "NLB target group protocol (TCP/TLS/UDP). ALB TG uses HTTP."
}

variable "target_type" {
  type        = string
  default     = "ip"
  description = "Target type: ip (ECS/Fargate) or instance (EC2/ASG)."
}

# Optional EC2/ASG attachments
variable "attach_instance_ids" {
  type        = list(string)
  default     = []
  description = "Optional EC2 instance IDs to attach to the TG."
}

variable "asg_name" {
  type        = string
  default     = ""
  description = "Optional Auto Scaling Group name to attach to the TG."
}

# Locals for naming and common tags
locals {
  name_prefix = var.name_prefix_override != null ? var.name_prefix_override : var.sandbox_name

  common_tags = merge(
    { Name = local.name_prefix },
    var.tags_extra
  )
}

