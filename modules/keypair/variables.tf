variable "enabled" {
  type    = bool
  default = false
}

# Optional escape hatch if you ever need to pin a specific name
variable "key_name_override" {
  type        = string
  default     = null
  description = "If set, this exact name is used for the AWS KeyPair & Secret."
}

variable "algorithm" {
  type    = string
  default = "RSA" # or "ED25519"
  validation {
    condition     = contains(["RSA", "ED25519"], var.algorithm)
    error_message = "algorithm must be RSA or ED25519."
  }
}

variable "rsa_bits" {
  type    = number
  default = 4096
}

variable "tags_extra" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged into all resources."
}

locals {
  key_name = coalesce(var.key_name_override, "keypair")
  common_tags = merge(
    { Name = local.key_name },
    var.tags_extra
  )
}
