# Merge Lambda execution role
# Reads Comprehend outputs (raw/) + writes enriched data to dual storage (DynamoDB + S3 curated/)
# Scoped: no read from processed/, no access to other buckets

resource "aws_iam_role" "merge_lambda" {
  name = "${local.resource_prefix}-merge-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-merge-lambda-role"
      Description = "Execution role for Merge Lambda"
    }
  )
}

# S3 write policy: processed/ (enriched data) + curated/ (pre-aggregated summary)
# Write only; no read from processed (prevents circular dependencies)

resource "aws_iam_role_policy" "s3_write" {
  name = "${local.resource_prefix}-merge-s3-write"
  role = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${var.data_lake_bucket_arn}/processed/*",
          "${var.data_lake_bucket_arn}/curated/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${var.data_lake_bucket_arn}/curated/*"
      }
    ]
  })
}

# Read raw/ to extract text preview and compute statistics (DecimalEncoder handles JSON serialization)

resource "aws_iam_role_policy" "s3_read" {
  name = "${local.resource_prefix}-merge-s3-read"
  role = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${var.data_lake_bucket_arn}/raw/*"
      }
    ]
  })
}

# DynamoDB write-only (PutItem only; no Scan, Query, GetItem for security)
# 30-day TTL auto-cleanup prevents cost growth

resource "aws_iam_role_policy" "dynamodb_write" {
  name = "${local.resource_prefix}-merge-dynamodb-write"
  role = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# AWS managed policy (preferred over inline for standard permissions)
resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.merge_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray write access for active tracing. PutTraceSegments/PutTelemetryRecords do not support
# resource-level permissions, so the wildcard is required by AWS.
# Ref: https://docs.aws.amazon.com/xray/latest/devguide/security_iam_id-based-policy-examples.html
resource "aws_iam_role_policy" "xray_write" {
  count = var.enable_xray_tracing ? 1 : 0
  name  = "${local.resource_prefix}-merge-xray-write"
  role  = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}
