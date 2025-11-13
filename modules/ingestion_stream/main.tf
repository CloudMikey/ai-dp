#-------------------- Streaming Ingestion Module --------------------#
# Creates API Gateway HTTP API and Kinesis Data Stream for real-time data ingestion
# Direct integration (no Lambda proxy) reduces latency and cost
# API Gateway → Kinesis → (later) Lambda ETL → S3

locals {
  resource_prefix       = "${var.project_name}-${var.environment}"
  stream_name           = "${local.resource_prefix}-ingestion-stream"
  api_name              = "${local.resource_prefix}-ingestion-api"
  lambda_name           = "${local.resource_prefix}-etl" # For Task 3 Lambda function
  eventbridge_rule_name = "${local.resource_prefix}-s3-batch-ingestion"
}

#-------------------- Kinesis Data Stream --------------------#
# Receives real-time data from API Gateway
# 1 shard = 1 MB/sec write capacity, 2 MB/sec read capacity
# Data retained for 24 hours by default (configurable 24-8760 hours)

resource "aws_kinesis_stream" "ingestion" {
  name             = local.stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_hours

  # Encryption: NONE (default, free) or KMS (additional cost)
  encryption_type = var.kinesis_encryption_type
  kms_key_id      = var.kinesis_encryption_type == "KMS" ? var.kinesis_kms_key_id : null

  # Stream mode: PROVISIONED (with shard_count) is simpler for portfolio projects
  # ON_DEMAND mode available but adds complexity for explaining costs in interviews
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  # Tags applied via provider default_tags in envs/*/main.tf
  tags = merge(
    var.tags,
    {
      Name        = local.stream_name
      Description = "Ingestion stream for real-time data"
    }
  )
}

#-------------------- IAM Role for API Gateway → Kinesis --------------------#
# Allows API Gateway to write records to Kinesis stream
# Trust policy: API Gateway service can assume this role
# Permissions: kinesis:PutRecord on the specific stream

resource "aws_iam_role" "api_gateway_kinesis" {
  name = "${local.resource_prefix}-apigw-kinesis-role"

  # Trust policy: Allow API Gateway service to assume this role
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

# Permissions policy: Allow PutRecord to Kinesis stream (least privilege)
resource "aws_iam_role_policy" "api_gateway_kinesis" {
  name = "kinesis-put-record"
  role = aws_iam_role.api_gateway_kinesis.id

  # Inline policy granting Kinesis write permissions
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

#-------------------- API Gateway HTTP API --------------------#
# Modern HTTP API (vs REST API): Simpler, cheaper, easier to explain
# ~70% cost reduction vs REST API for this use case
# Handles CORS, direct AWS service integration

resource "aws_apigatewayv2_api" "ingestion" {
  name          = local.api_name
  protocol_type = "HTTP"
  description   = "HTTP API for real-time data ingestion to Kinesis"

  # CORS configuration for dev/testing
  # Allows web clients to call the API during development
  dynamic "cors_configuration" {
    for_each = var.enable_cors ? [1] : []

    content {
      allow_origins = var.cors_allow_origins
      allow_methods = var.cors_allow_methods
      allow_headers = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
      max_age       = 300
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = local.api_name
      Description = "Ingestion API for streaming data"
    }
  )
}

#-------------------- API Gateway Integration (API → Kinesis) --------------------#
# Direct integration using Kinesis-PutRecord action
# Request mapping: JSON body → Kinesis record
# No Lambda proxy = lower latency, no cold starts

resource "aws_apigatewayv2_integration" "kinesis" {
  api_id              = aws_apigatewayv2_api.ingestion.id
  integration_type    = "AWS_PROXY"
  integration_subtype = "Kinesis-PutRecord"

  # IAM role for API Gateway to call Kinesis
  credentials_arn = aws_iam_role.api_gateway_kinesis.arn

  # Request parameters mapping
  # Maps API Gateway request to Kinesis PutRecord parameters
  request_parameters = {
    StreamName   = aws_kinesis_stream.ingestion.name
    Data         = "$request.body"
    PartitionKey = "$request.header.X-Partition-Key"
  }

  # Payload format version for AWS service integrations
  payload_format_version = "1.0"
}

#-------------------- API Gateway Route --------------------#
# POST /ingest route that triggers Kinesis integration
# Clients send JSON payloads to this endpoint

resource "aws_apigatewayv2_route" "ingest" {
  api_id    = aws_apigatewayv2_api.ingestion.id
  route_key = "POST /ingest"

  # Target: The Kinesis integration created above
  target = "integrations/${aws_apigatewayv2_integration.kinesis.id}"
}

#-------------------- API Gateway Stage --------------------#
# Default stage with auto-deploy
# HTTP APIs use $default stage for simplicity

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.ingestion.id
  name        = "$default"
  auto_deploy = true

  # Access logging to CloudWatch (if enabled)
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []

    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn

      # Log format for HTTP APIs (JSON format for easy parsing)
      format = jsonencode({
        requestId        = "$context.requestId"
        ip               = "$context.identity.sourceIp"
        requestTime      = "$context.requestTime"
        httpMethod       = "$context.httpMethod"
        routeKey         = "$context.routeKey"
        status           = "$context.status"
        protocol         = "$context.protocol"
        responseLength   = "$context.responseLength"
        integrationError = "$context.integrationErrorMessage"
      })
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.api_name}-default-stage"
      Description = "Default stage for ingestion API"
    }
  )
}

#-------------------- CloudWatch Log Group for API Gateway --------------------#
# Stores API Gateway access logs for debugging and monitoring
# Only created if logging is enabled

resource "aws_cloudwatch_log_group" "api_gateway" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.api_gateway_log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${local.api_name}-logs"
      Description = "Access logs for ingestion API"
    }
  )
}

#-------------------- Lambda Code Packaging --------------------#
# Archives Lambda Python code into deployment-ready ZIP file
# Terraform automatically detects code changes via source_code_hash

data "archive_file" "etl_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/etl"
  output_path = "${path.module}/../../lambdas/etl/lambda_etl.zip"

  # Exclude unnecessary files from package
  excludes = [
    "lambda_etl.zip",
    "__pycache__",
    "*.pyc",
    ".pytest_cache"
  ]
}

#-------------------- SQS Dead Letter Queue --------------------#
# Stores failed Kinesis records for debugging and replay
# After max retries, failed Lambda invocations send messages here

resource "aws_sqs_queue" "etl_dlq" {
  name = "${local.resource_prefix}-etl-dlq"

  # Retention period: 14 days (balances debugging time vs. cost)
  message_retention_seconds = 1209600 # 14 days

  # Enable encryption at rest (optional for dev, recommended for prod)
  # sqs_managed_sse_enabled = true  # Uncomment for encryption

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-etl-dlq"
      Description = "Dead letter queue for failed ETL Lambda processing"
      Purpose     = "ErrorHandling"
    }
  )
}

#-------------------- CloudWatch Log Group for Lambda --------------------#
# Stores Lambda function logs for debugging and monitoring
# Retention period configurable per environment (7d dev, 30d+ prod)
# NOTE: Lambda function resource will be created in Task 3

resource "aws_cloudwatch_log_group" "etl_lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7 # Default retention, will be made variable in Task 3

  tags = merge(
    var.tags,
    {
      Name        = "${local.lambda_name}-logs"
      Description = "CloudWatch logs for ETL Lambda function"
    }
  )
}

#-------------------- Lambda IAM Role --------------------#
# Execution role for ETL Lambda function
# Permissions: Kinesis read, S3 write, CloudWatch logs, SQS (DLQ)

resource "aws_iam_role" "etl_lambda" {
  name = "${local.resource_prefix}-etl-lambda-role"

  # Trust policy: Allow Lambda service to assume this role
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

# Attach AWS managed policy for basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.etl_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach AWS managed policy for Kinesis stream consumer
resource "aws_iam_role_policy_attachment" "lambda_kinesis_execution" {
  role       = aws_iam_role.etl_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}

# Inline policy for S3 write access (least privilege - only to data lake bucket)
resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "s3-data-lake-write"
  role = aws_iam_role.etl_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        # Scoped to only raw/ prefix in data lake bucket
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

#-------------------- Lambda Function --------------------#
# ETL Lambda: Reads from Kinesis, validates, writes to S3 raw/
# Triggered automatically by Kinesis event source mapping

resource "aws_lambda_function" "etl" {
  function_name = local.lambda_name
  description   = "ETL function: Kinesis → S3 raw layer with validation and normalization"

  # Deployment package (created by archive_file data source)
  filename         = data.archive_file.etl_lambda.output_path
  source_code_hash = data.archive_file.etl_lambda.output_base64sha256

  # Runtime configuration
  runtime = "python3.11"
  handler = "app.lambda_handler"
  timeout = 60 # 60 seconds (Kinesis batch processing may take time)

  # Memory allocation (128 MB is minimum, increase if processing large batches)
  memory_size = 256 # 256 MB for JSON processing

  # IAM role for execution
  role = aws_iam_role.etl_lambda.arn

  # Environment variables
  environment {
    variables = {
      DATA_LAKE_BUCKET = var.data_lake_bucket_name
      RAW_PREFIX       = "raw/"
      LOG_LEVEL        = "INFO"
    }
  }

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.etl_dlq.arn
  }

  # Tracing configuration (optional - adds X-Ray costs)
  # tracing_config {
  #   mode = "Active"
  # }

  # Ensure log group exists before Lambda
  depends_on = [
    aws_cloudwatch_log_group.etl_lambda,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]

  tags = merge(
    var.tags,
    {
      Name        = local.lambda_name
      Description = "ETL Lambda for Kinesis to S3 ingestion"
      Component   = "DataIngestion"
    }
  )
}

#-------------------- Lambda Event Source Mapping --------------------#
# Connects Kinesis stream to Lambda function
# Lambda polls Kinesis and processes records in batches

resource "aws_lambda_event_source_mapping" "kinesis_to_etl" {
  event_source_arn  = aws_kinesis_stream.ingestion.arn
  function_name     = aws_lambda_function.etl.arn
  starting_position = "LATEST" # Start processing new records (not historical)

  # Batch configuration
  batch_size                         = 100 # Process up to 100 records per invocation
  maximum_batching_window_in_seconds = 5   # Wait up to 5 seconds to collect batch
  parallelization_factor             = 1   # Number of concurrent batches per shard

  # Error handling configuration
  maximum_retry_attempts = 3 # Retry failed batches 3 times before sending to DLQ

  # Failed records destination (DLQ)
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.etl_dlq.arn
    }
  }

  # Ensure Lambda function is ready before creating mapping
  depends_on = [
    aws_iam_role_policy_attachment.lambda_kinesis_execution,
    aws_lambda_function.etl
  ]
}

#-------------------- EventBridge Rule (Batch Ingestion Detection) --------------------#
# Detects batch file uploads to the data lake raw/ layer
# Triggers on S3 Object Created events, filtered to raw/ prefix only
# Note: NO target configured yet - target added in Phase 4 after Step Functions exists

resource "aws_cloudwatch_event_rule" "s3_batch_ingestion" {
  name        = local.eventbridge_rule_name
  description = "Detects batch file uploads to raw/ layer for Step Functions processing"

  # Event pattern: S3 Object Created in data lake bucket, raw/ prefix only
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.data_lake_bucket_name]
      }
      object = {
        key = [{
          prefix = "raw/"
        }]
      }
    }
  })

  state = "ENABLED"

  tags = merge(
    var.tags,
    {
      Name        = local.eventbridge_rule_name
      Description = "Batch ingestion detection for Step Functions orchestration"
      Component   = "EventBridge"
    }
  )
}

#-------------------- IAM Role for EventBridge → Step Functions --------------------#
# Allows EventBridge to start Step Functions executions
# Only created when create_eventbridge_target = true (Phase 4, Task 3)
# Trust policy: EventBridge service can assume this role

resource "aws_iam_role" "eventbridge_step_functions" {
  count = var.create_eventbridge_target ? 1 : 0
  name  = "${local.resource_prefix}-eventbridge-sfn-role"

  # Trust policy: Allow EventBridge service to assume this role
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

#-------------------- IAM Policy for Step Functions Invocation --------------------#
# Permission for EventBridge to start executions on the specific state machine
# Least privilege: scoped to only the state machine ARN provided

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

#-------------------- EventBridge Target (EventBridge → Step Functions) --------------------#
# Connects the EventBridge rule to the Step Functions state machine
# When S3 files are uploaded to raw/, EventBridge triggers Step Functions execution
# Only created when create_eventbridge_target = true (Phase 4, Task 3)

resource "aws_cloudwatch_event_target" "step_functions" {
  count     = var.create_eventbridge_target ? 1 : 0
  rule      = aws_cloudwatch_event_rule.s3_batch_ingestion.name
  target_id = "StepFunctionsOrchestrator"
  arn       = var.state_machine_arn
  role_arn  = aws_iam_role.eventbridge_step_functions[0].arn
}
