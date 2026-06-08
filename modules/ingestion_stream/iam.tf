# API Gateway integration for HTTP API → Kinesis direct writes
# Direct PutRecord is more efficient than Lambda proxy integration (lower latency, cost)

resource "aws_iam_role" "api_gateway_kinesis" {
  name = "${local.resource_prefix}-apigw-kinesis-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-apigw-kinesis-role"
      Description = "Allows API Gateway to write to Kinesis stream"
    }
  )
}

resource "aws_iam_role_policy" "api_gateway_kinesis" {
  name = "kinesis-put-record"
  role = aws_iam_role.api_gateway_kinesis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        # Scoped to only this specific Kinesis stream (least privilege)
        Resource = aws_kinesis_stream.ingestion.arn
      }
    ]
  })
}

# Execution role for ETL Lambda (Kinesis consumer)
# Reads records from stream, writes normalized JSON to S3 raw/, publishes failures to DLQ

resource "aws_iam_role" "etl_lambda" {
  name = "${local.resource_prefix}-etl-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-etl-lambda-role"
      Description = "Execution role for ETL Lambda function"
    }
  )
}

# AWS managed policies handle standard permissions (logs, Kinesis stream reads)
# Inline policies below handle custom scopes (S3 raw/ only, DLQ only)

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.etl_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_kinesis_execution" {
  role       = aws_iam_role.etl_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}

# S3 writes scoped to raw/ prefix only (no bucket policy, no object ACLs)
# ACLs removed: deprecated in favor of bucket-level policies; Lambda doesn't need ACL write
resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "s3-data-lake-write"
  role = aws_iam_role.etl_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.data_lake_bucket_arn}/raw/*"
      }
    ]
  })
}

# Inline policy for SQS DLQ access (for failed record handling)
resource "aws_iam_role_policy" "lambda_sqs_dlq" {
  name = "sqs-dlq-access"
  role = aws_iam_role.etl_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.etl_dlq.arn
      }
    ]
  })
}

# EventBridge → Step Functions integration for batch processing
# Triggered when S3 raw/ receives new files; orchestrates AI enrichment workflow

resource "aws_iam_role" "eventbridge_step_functions" {
  count = var.create_eventbridge_target ? 1 : 0
  name  = "${local.resource_prefix}-eventbridge-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-eventbridge-sfn-role"
      Description = "Allows EventBridge to invoke Step Functions state machine"
    }
  )
}

# Scoped to specific state machine ARN only (least privilege)
resource "aws_iam_role_policy" "eventbridge_step_functions" {
  count = var.create_eventbridge_target ? 1 : 0
  name  = "start-execution"
  role  = aws_iam_role.eventbridge_step_functions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = var.state_machine_arn
      }
    ]
  })
}
