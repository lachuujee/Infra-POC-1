data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_canonical_user_id" "current" {}

# Minimal locals only for harmless formatting
locals {
  name_clean    = replace(var.name, "_", "-")
  origin_prefix = var.origin_path != "" ? trim(var.origin_path, "/") : null
}

# =========================
# ORIGIN S3 (private, OAC)
# =========================
resource "aws_s3_bucket" "origin" {
  count         = var.enabled ? 1 : 0
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = var.common_tags
}

resource "aws_s3_bucket_ownership_controls" "origin" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.origin[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "origin" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.origin[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "origin" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.origin[0].id

  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.origin[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_id == null ? null : var.kms_key_id
    }
  }
}

# Create zero-byte "folder" for the origin path (e.g., frontend/)
resource "aws_s3_object" "origin_prefix" {
  count   = var.enabled && local.origin_prefix != null ? 1 : 0
  bucket  = aws_s3_bucket.origin[0].id
  key     = "${local.origin_prefix}/"
  content = ""
}

# ==========================================
# LOGS S3 (separate bucket; ACLs for CF logs)
# ==========================================
resource "aws_s3_bucket" "logs" {
  count         = var.enabled && var.enable_logging ? 1 : 0
  bucket        = var.logs_bucket_name
  force_destroy = var.force_destroy
  tags          = var.common_tags
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.enabled && var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  # Allow ACLs for CloudFront log delivery
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.enabled && var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enabled && var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_acl" "logs" {
  count  = var.enabled && var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  access_control_policy {
    owner {
      id = data.aws_canonical_user_id.current.id
    }

    # CloudFront log delivery canonical user
    grant {
      grantee {
        type = "CanonicalUser"
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
      }
      permission = "FULL_CONTROL"
    }

    # Bucket owner
    grant {
      grantee {
        type = "CanonicalUser"
        id   = data.aws_canonical_user_id.current.id
      }
      permission = "FULL_CONTROL"
    }
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.logs
  ]
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.enabled && var.enable_logging && var.log_expire_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "expire"
    status = "Enabled"

    expiration {
      days = var.log_expire_days
    }

    filter {
      prefix = ""
    }
  }
}

# ============
# CloudFront
# ============
resource "aws_cloudfront_origin_access_control" "oac" {
  count                             = var.enabled ? 1 : 0
  name                              = "${local.name_clean}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "security" {
  count = var.enabled ? 1 : 0
  name  = "${local.name_clean}-security"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer-when-downgrade"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }
  }
}

resource "aws_cloudfront_cache_policy" "static" {
  count = var.enabled ? 1 : 0
  name  = "${local.name_clean}-static-${var.default_ttl_seconds}s"

  default_ttl = var.default_ttl_seconds
  max_ttl     = var.default_ttl_seconds
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = var.compress
    enable_accept_encoding_gzip   = var.compress

    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  count               = var.enabled ? 1 : 0
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.price_class
  http_version        = "http2and3"
  default_root_object = var.default_root_object
  aliases             = var.acm_enabled && length(var.aliases) > 0 ? var.aliases : []

  origin {
    domain_name              = "${var.bucket_name}.s3.${data.aws_region.current.name}.amazonaws.com"
    origin_id                = "s3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac[0].id
    origin_path              = var.origin_path
  }

  default_cache_behavior {
    target_origin_id       = "s3-${var.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = aws_cloudfront_cache_policy.static[0].id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id
    compress                   = var.compress
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_enabled ? false : true
    acm_certificate_arn            = var.acm_enabled && var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_enabled ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  dynamic "logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      bucket          = "${aws_s3_bucket.logs[0].bucket}.s3.amazonaws.com"
      include_cookies = false
      prefix          = coalesce(var.log_prefix, (var.request_id != "" ? var.request_id : var.name))
    }
  }

  tags = var.common_tags
}

# ===================================
# S3 Bucket policy: OAC-only access
# ===================================
data "aws_iam_policy_document" "oac_read" {
  count = var.enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "origin" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.origin[0].id
  policy = data.aws_iam_policy_document.oac_read[0].json
}
