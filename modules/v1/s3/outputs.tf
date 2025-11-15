output "bucket_name" {
  value       = var.enabled ? aws_s3_bucket.this[0].bucket : null
  description = "S3 bucket name"
}

output "bucket_arn" {
  value       = var.enabled ? aws_s3_bucket.this[0].arn : null
  description = "S3 bucket ARN"
}
