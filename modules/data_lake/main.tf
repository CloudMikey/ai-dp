#-------------------- Data Lake S3 Bucket --------------------#
# Three-layer data lake: raw/ (ingested), processed/ (AI-enriched), curated/ (business-ready)

locals {
  bucket_name = "${var.project_name}-data-lake-${var.environment}-${var.aws_region}"
}

#-------------------- S3 Bucket --------------------#

resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name
}

#-------------------- Versioning --------------------#

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

#-------------------- Encryption --------------------#

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
# Cost optimization: Transition older data to cheaper storage tiers

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id


  rule {
    id     = "raw-layer-lifecycle"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    dynamic "transition" {
      for_each = var.raw_layer_lifecycle.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = var.raw_layer_lifecycle.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.raw_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = var.raw_layer_lifecycle.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    dynamic "expiration" {
      for_each = var.raw_layer_lifecycle.expiration_days > 0 ? [1] : []
      content {
        days = var.raw_layer_lifecycle.expiration_days
      }
    }


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


  rule {
    id     = "processed-layer-lifecycle"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    dynamic "transition" {
      for_each = var.processed_layer_lifecycle.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = var.processed_layer_lifecycle.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.processed_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = var.processed_layer_lifecycle.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    dynamic "expiration" {
      for_each = var.processed_layer_lifecycle.expiration_days > 0 ? [1] : []
      content {
        days = var.processed_layer_lifecycle.expiration_days
      }
    }


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

  # Curated layer lifecycle (conditionally created only if actions configured)
  dynamic "rule" {
    for_each = var.curated_layer_lifecycle.transition_to_ia_days > 0 || var.curated_layer_lifecycle.transition_to_glacier_days > 0 || var.curated_layer_lifecycle.expiration_days > 0 ? [1] : []
    
    content {
      id     = "curated-layer-lifecycle"
      status = "Enabled"

      filter {
        prefix = "curated/"
      }

      dynamic "transition" {
        for_each = var.curated_layer_lifecycle.transition_to_ia_days > 0 ? [1] : []
        content {
          days          = var.curated_layer_lifecycle.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "transition" {
        for_each = var.curated_layer_lifecycle.transition_to_glacier_days > 0 ? [1] : []
        content {
          days          = var.curated_layer_lifecycle.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }

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

#-------------------- EventBridge Notification --------------------#

resource "aws_s3_bucket_notification" "eventbridge" {
  bucket      = aws_s3_bucket.data_lake.id
  eventbridge = true
}
