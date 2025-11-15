output "distribution_id" {
  value       = length(aws_cloudfront_distribution.this) > 0 ? aws_cloudfront_distribution.this[0].id : null
  description = "CloudFront distribution ID"
}

output "distribution_domain_name" {
  value       = length(aws_cloudfront_distribution.this) > 0 ? aws_cloudfront_distribution.this[0].domain_name : null
  description = "CloudFront default domain name"
}

output "distribution_arn" {
  value       = length(aws_cloudfront_distribution.this) > 0 ? aws_cloudfront_distribution.this[0].arn : null
  description = "CloudFront distribution ARN"
}

output "origin_bucket_name" {
  value       = length(aws_s3_bucket.origin) > 0 ? aws_s3_bucket.origin[0].bucket : null
  description = "Origin S3 bucket name"
}

output "logs_bucket_name" {
  value       = length(aws_s3_bucket.logs) > 0 ? aws_s3_bucket.logs[0].bucket : null
  description = "CloudFront access-logs S3 bucket name"
}
