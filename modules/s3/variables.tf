variable "region" {
  type        = string
  description = "AWS region for this module's provider"
}

variable "enabled" {
  type    = bool
  default = true
}

# Display name coming from inputs.json: modules.s3.name (e.g., "SBX_INTAKE_ID_001-s3")
variable "name" {
  type    = string
  default = "s3"
}

# Required to help build a globally unique bucket name
variable "request_id" {
  type = string
}

# Controls
variable "versioning" {
  type    = bool
  default = true
}

variable "block_public" {
  type    = bool
  default = true
}

variable "force_destroy" {
  type    = bool
  default = false
}

# Encryption
variable "kms_key_id" {
  type    = string
  default = null   # null → SSE via AWS-managed KMS (alias/aws/s3); else customer KMS
}

# Optional hard override for the actual bucket name (must be globally unique, DNS-compliant)
variable "bucket_name_override" {
  type    = string
  default = null
}

# Extra tags merged into all resources
variable "tags_extra" {
  type    = map(string)
  default = {}
}

locals {
  # S3 bucket DNS rules: lowercase, no underscores
  name_clean = lower(replace(var.name, "_", "-"))
  req_clean  = lower(replace(var.request_id, "_", "-"))

  # Default bucket name pattern: "<name>-<request_id>"
  bucket_name_default = "${local.name_clean}-${local.req_clean}"

  bucket_name = coalesce(var.bucket_name_override, local.bucket_name_default)

  common_tags = merge(
    {
      Name    = local.bucket_name
      Service = "S3"
    },
    var.tags_extra
  )
}
