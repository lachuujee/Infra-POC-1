output "key_name" {
  description = "KeyPair name to use in EC2 (and the Secret name)"
  value       = var.enabled ? local.key_name : null
}

output "key_pair_id" {
  description = "AWS KeyPair ID"
  value       = var.enabled ? aws_key_pair.this[0].id : null
}

output "private_key_secret_arn" {
  description = "Secrets Manager ARN holding the private key PEM"
  value       = var.enabled ? aws_secretsmanager_secret.pk[0].arn : null
}

output "private_key_secret_version_id" {
  description = "Secrets Manager version ID for the private key"
  value       = var.enabled ? aws_secretsmanager_secret_version.pkv[0].version_id : null
}
