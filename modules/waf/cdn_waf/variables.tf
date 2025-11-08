variable "enabled" {
  type        = bool
  default     = true
  description = "Enable/disable the CDN WAF resources."
}

variable "name" {
  type        = string
  description = "Logical CDN name, e.g., sbx_intake_id_001_cdn"
}

variable "request_id" {
  type        = string
  default     = ""
  description = "Request/Intake ID for tagging."
}

variable "intake_id" {
  type        = string
  default     = ""
  description = "Intake folder id used to locate CDN state."
}

variable "tags_extra" {
  type        = map(string)
  default     = {}
  description = "Additional tags to merge with { Name = var.name }."
}

variable "remote_state_bucket" {
  type        = string
  default     = "wbd-tf-state-sandbox"
  description = "S3 bucket for remote state lookups."
}

variable "remote_state_region" {
  type        = string
  default     = "us-east-1"
  description = "Region for the remote state bucket."
}

variable "log_to_cloudwatch" {
  type        = bool
  default     = true
  description = "Enable WAF logging to CloudWatch Logs."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch Logs retention in days."
}

variable "common_tags" {
  type        = map(string)
  default     = {}
  description = "Fully-resolved common tags passed from Terragrunt."
}
