variable "region" {
  type        = string
  default     = null
  description = "AWS region for context; module uses provider region."
}

variable "enabled" {
  type        = bool
  default     = true
  description = "Enable/disable the CDN resources."
}

variable "name" {
  type        = string
  description = "Logical name for the CDN, e.g., sbx_intake_id_001_cdn"
}

variable "request_id" {
  type        = string
  default     = ""
  description = "Request/Intake ID for tagging and prefixes."
}

# === Computed in Terragrunt and passed in ===
variable "bucket_name" {
  type        = string
  description = "Origin S3 bucket name (hyphenated). Computed in Terragrunt."
}

variable "logs_bucket_name" {
  type        = string
  description = "CloudFront logs S3 bucket name. Computed in Terragrunt."
}

variable "common_tags" {
  type        = map(string)
  default     = {}
  description = "Fully-resolved common tags. Computed in Terragrunt."
}

# === Module defaults live here (NOT in Terragrunt) ===
variable "versioning" {
  type        = bool
  default     = true
  description = "Enable versioning on the created origin bucket."
}

variable "block_public" {
  type        = bool
  default     = true
  description = "Block all public access on the created origin bucket."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Force-destroy created buckets."
}

variable "kms_key_id" {
  type        = string
  default     = null
  description = "KMS key for SSE-KMS on the origin bucket. Null uses AES256."
}

variable "default_root_object" {
  type        = string
  default     = "index.html"
  description = "Default landing page."
}

variable "default_ttl_seconds" {
  type        = number
  default     = 259200
  description = "Default/max TTL (3 days)."
}

variable "compress" {
  type        = bool
  default     = true
  description = "Enable gzip/brotli."
}

variable "price_class" {
  type        = string
  default     = "PriceClass_All"
  description = "Edge coverage."
}

variable "acm_enabled" {
  type        = bool
  default     = false
  description = "Attach ACM & aliases if true."
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "us-east-1 ACM ARN (when enabled)."
}

variable "aliases" {
  type        = list(string)
  default     = []
  description = "Alternate domain names."
}

variable "multitenancy_enabled" {
  type        = bool
  default     = false
  description = "Host-based multitenancy toggle."
}

variable "origin_path" {
  type        = string
  default     = "/frontend"
  description = "Origin path prefix; must start with '/' or be empty."
}

variable "enable_logging" {
  type        = bool
  default     = true
  description = "Enable CloudFront access logs to S3."
}

variable "log_expire_days" {
  type        = number
  default     = 90
  description = "Logs lifecycle expiration (days)."
}

variable "log_prefix" {
  type        = string
  default     = null
  description = "Logs prefix; null uses request_id or name."
}
