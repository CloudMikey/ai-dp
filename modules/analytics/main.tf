locals {
  resource_prefix       = "${var.project_name}-${var.environment}"
  athena_results_bucket = "${var.project_name}-athena-results-${var.environment}-${var.aws_region}"
}

resource "aws_glue_catalog_database" "analytics" {
  name        = "${local.resource_prefix}-analytics"
  description = "Data Catalog database for AI-DP processed data analytics"
}

# Automatically discovers schema and partitions from S3 JSON files
# Runs on-demand to catalog processed/ layer

resource "aws_glue_crawler" "processed_data" {
  name          = "${local.resource_prefix}-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = aws_glue_catalog_database.analytics.name
  description   = "Crawls S3 processed/ layer to infer schema and detect partitions"

  s3_target {
    path = "s3://${var.data_lake_bucket_name}/processed/"
  }

  # UPDATE_IN_DATABASE: Auto-update schema when new enrichment fields appear
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "DELETE_FROM_DATABASE"
  }

  # CRAWL_EVERYTHING: Required for UPDATE_IN_DATABASE schema policy
  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  # Partition detection configuration
  # Automatically detects year/month/day partitions from S3 folder structure
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = merge(
    var.tags,
    {
      Name      = "${local.resource_prefix}-crawler"
      Component = "Analytics"
      Purpose   = "SchemaDiscovery"
    }
  )
}

# Stores Athena query outputs with 7-day automatic cleanup

resource "aws_s3_bucket" "athena_results" {
  bucket = local.athena_results_bucket

  tags = merge(
    var.tags,
    {
      Name        = local.athena_results_bucket
      Component   = "Analytics"
      Purpose     = "AthenaQueryResults"
      Description = "Temporary storage for Athena query outputs"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 7-day lifecycle: Query results are temporary
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "delete-old-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Enforces consistent query settings and S3 output location

resource "aws_athena_workgroup" "dev" {
  name        = "${local.resource_prefix}-workgroup"
  description = "Athena workgroup for ${var.environment} environment analytics queries"
  state       = "ENABLED"

  configuration {
    bytes_scanned_cutoff_per_query = 1073741824
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"

      #Secure temp files made in the query process that put into a EBS volume thats part of Athena
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "AUTO"
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-workgroup"
      Component   = "Analytics"
      Environment = var.environment
    }
  )
}