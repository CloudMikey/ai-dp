#-------------------- AWS Provider --------------------#

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        ManagedBy   = "terraform"
        Purpose     = "terraform-state"
        Environment = "shared"
      },
      var.tags
    )
  }
}

#-------------------- S3 Bucket for Terraform State --------------------#

# Main S3 bucket for storing Terraform state files
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bootstrap_s3

  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files for all environments"
  }
}

#-------------------- S3 Bucket Versioning --------------------#

# Enable versioning to protect against accidental state file deletion or corruption
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

#-------------------- S3 Bucket Encryption --------------------#

# Encrypt state files at rest using AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

#-------------------- S3 Bucket Public Access Block --------------------#

# Block all public access to the state bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#-------------------- S3 Bucket Lifecycle Rules --------------------#

# Automatically delete old versions of state files to reduce storage costs
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  count  = var.enable_lifecycle_rules ? 1 : 0
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {} # Apply to all objects in the bucket

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "delete-incomplete-multipart-uploads"
    status = "Enabled"

    filter {} # Apply to all objects in the bucket

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

#-------------------- S3 Bucket Logging (Optional) --------------------#

# Note: Uncomment if you want access logging for the state bucket
# You'll need to create a separate logging bucket first

# resource "aws_s3_bucket_logging" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   target_bucket = aws_s3_bucket.logs.id
#   target_prefix = "terraform-state-logs/"
# }

#-------------------- S3 Bucket Policy --------------------#

# Enforce SSL/TLS for all connections to the state bucket
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforcedTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
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
