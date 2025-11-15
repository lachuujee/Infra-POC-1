locals { create = var.enabled ? 1 : 0 }

resource "aws_s3_bucket" "this" {
  count         = local.create
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  count  = local.create
  bucket = aws_s3_bucket.this[0].id
  block_public_acls       = var.block_public
  block_public_policy     = var.block_public
  ignore_public_acls      = var.block_public
  restrict_public_buckets = var.block_public
}

resource "aws_s3_bucket_versioning" "this" {
  count  = local.create
  bucket = aws_s3_bucket.this[0].id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

# encryption: AWS-managed if kms_key_id is null; else customer KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "managed" {
  count  = local.create * (var.kms_key_id == null ? 1 : 0)
  bucket = aws_s3_bucket.this[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "customer" {
  count  = local.create * (var.kms_key_id != null ? 1 : 0)
  bucket = aws_s3_bucket.this[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
  }
}

# deny non-TLS access
resource "aws_s3_bucket_policy" "tls_only" {
  count  = local.create
  bucket = aws_s3_bucket.this[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "DenyInsecureTransport",
      Effect    = "Deny",
      Principal = "*",
      Action    = "s3:*",
      Resource  = [
        aws_s3_bucket.this[0].arn,
        "${aws_s3_bucket.this[0].arn}/*"
      ],
      Condition = { Bool = { "aws:SecureTransport": "false" } }
    }]
  })
}
