#-------------------- Data Lake S3 Bucket --------------------#
# Creates a single S3 bucket with three logical layers using prefixes:
# - raw/: Ingested data (from Kinesis or batch uploads)
# - processed/: AI-enriched data ready for analytics
# - curated/: Aggregated, business-ready datasets

locals {
  bucket_name = "${var.project_name}-data-lake-${var.environment}-${var.aws_region}"
}

#-------------------- S3 Bucket Resource --------------------#

resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name

  # All tags applied via provider default_tags in envs/*/main.tf
  # Additional resource-specific tags can be added if needed
}

#-------------------- Versioning Configuration --------------------#

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

#-------------------- Encryption Configuration --------------------#

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null ? true : false
  }
}

#-------------------- Block Public Access --------------------#

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#-------------------- Lifecycle Policies --------------------#
# Cost optimization: Transition older data to cheaper storage classes

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  # Raw layer lifecycle policy
  rule {
    id     = "raw-layer-lifecycle"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    # Transition to Infrequent Access
    dynamic "transition" {
      for_each = var.raw_layer_lifecycle.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = var.raw_layer_lifecycle.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    # Transition to Glacier
    dynamic "transition" {
      for_each = var.raw_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = var.raw_layer_lifecycle.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    # Expiration
    dynamic "expiration" {
      for_each = var.raw_layer_lifecycle.expiration_days > 0 ? [1] : []
      content {
        days = var.raw_layer_lifecycle.expiration_days
      }
    }

    # Also apply to noncurrent versions if versioning is enabled
    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning && var.raw_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
      content {
        noncurrent_days = var.raw_layer_lifecycle.transition_to_glacier_days
        storage_class   = "GLACIER"
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_versioning && var.raw_layer_lifecycle.expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = var.raw_layer_lifecycle.expiration_days
      }
    }
  }

  # Processed layer lifecycle policy
  rule {
    id     = "processed-layer-lifecycle"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    # Transition to Infrequent Access
    dynamic "transition" {
      for_each = var.processed_layer_lifecycle.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = var.processed_layer_lifecycle.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    # Transition to Glacier
    dynamic "transition" {
      for_each = var.processed_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = var.processed_layer_lifecycle.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    # Expiration
    dynamic "expiration" {
      for_each = var.processed_layer_lifecycle.expiration_days > 0 ? [1] : []
      content {
        days = var.processed_layer_lifecycle.expiration_days
      }
    }

    # Also apply to noncurrent versions
    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning && var.processed_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
      content {
        noncurrent_days = var.processed_layer_lifecycle.transition_to_glacier_days
        storage_class   = "GLACIER"
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_versioning && var.processed_layer_lifecycle.expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = var.processed_layer_lifecycle.expiration_days
      }
    }
  }

  # Curated layer lifecycle policy (only created if at least one action is configured)
  # If all lifecycle values are 0, this rule is omitted entirely
  dynamic "rule" {
    for_each = var.curated_layer_lifecycle.transition_to_ia_days > 0 || var.curated_layer_lifecycle.transition_to_glacier_days > 0 || var.curated_layer_lifecycle.expiration_days > 0 ? [1] : []
    
    content {
      id     = "curated-layer-lifecycle"
      status = "Enabled"

      filter {
        prefix = "curated/"
      }

      # Transition to Infrequent Access
      dynamic "transition" {
        for_each = var.curated_layer_lifecycle.transition_to_ia_days > 0 ? [1] : []
        content {
          days          = var.curated_layer_lifecycle.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      # Transition to Glacier
      dynamic "transition" {
        for_each = var.curated_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
        content {
          days          = var.curated_layer_lifecycle.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }

      # Expiration
      dynamic "expiration" {
        for_each = var.curated_layer_lifecycle.expiration_days > 0 ? [1] : []
        content {
          days = var.curated_layer_lifecycle.expiration_days
        }
      }
    }
  }
}

#-------------------- Bucket Policy - TLS Enforcement --------------------#
# Deny all requests that don't use HTTPS

resource "aws_s3_bucket_policy" "enforce_tls" {
  bucket = aws_s3_bucket.data_lake.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
