#-------------------- Merge Lambda Module --------------------#
# Combines AI enrichment → S3 processed/ + DynamoDB

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  lambda_name     = "${local.resource_prefix}-merge"
}

#-------------------- Lambda Code Packaging --------------------#

data "archive_file" "merge_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/merge"
  output_path = "${path.module}/../../lambdas/merge/lambda_merge.zip"

  excludes = [
    "lambda_merge.zip",
    "__pycache__",
    "*.pyc",
    ".pytest_cache"
  ]
}

#-------------------- Dead Letter Queue --------------------#

resource "aws_sqs_queue" "merge_dlq" {
  name = "${local.resource_prefix}-merge-dlq"

  message_retention_seconds = 1209600

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-merge-dlq"
      Description = "Dead letter queue for failed Merge Lambda processing"
      Purpose     = "ErrorHandling"
    }
  )
}

#-------------------- CloudWatch Log Group --------------------#

resource "aws_cloudwatch_log_group" "merge_lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${local.lambda_name}-logs"
      Description = "CloudWatch logs for Merge Lambda function"
    }
  )
}

#-------------------- Lambda Function --------------------#

resource "aws_lambda_function" "merge" {
  function_name = local.lambda_name
  description   = "Merge AI enrichment results and write to S3 processed layer + DynamoDB hot store"

  filename         = data.archive_file.merge_lambda.output_path
  source_code_hash = data.archive_file.merge_lambda.output_base64sha256

  runtime     = "python3.11"
  handler     = "merge_handler.lambda_handler"
  timeout     = 60  # Covers S3 GetObject + 3x DynamoDB/S3 writes + Step Functions response; load test P95=2044ms well within limit
  memory_size = 256 # 256MB sufficient for JSON enrichment merge + DecimalEncoder serialization; no large in-memory datasets

  role = aws_iam_role.merge_lambda.arn

  environment {
    variables = {
      DATA_LAKE_BUCKET = var.data_lake_bucket_name
      PROCESSED_PREFIX = var.processed_prefix
      DYNAMODB_TABLE   = var.dynamodb_table_name
      TTL_DAYS         = var.ttl_days
      LOG_LEVEL        = var.log_level
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.merge_dlq.arn
  }

  depends_on = [
    aws_cloudwatch_log_group.merge_lambda,
    aws_iam_role_policy.s3_write,
    aws_iam_role_policy.dynamodb_write,
    aws_iam_role_policy.dlq_write
  ]

  tags = merge(
    var.tags,
    {
      Name        = local.lambda_name
      Description = "Merge AI enrichment results"
      Component   = "Orchestration"
    }
  )
}
