# Direct API Gateway â†’ Kinesis integration (no Lambda proxy for lower latency)

locals {
  resource_prefix       = "${var.project_name}-${var.environment}"
  stream_name           = "${local.resource_prefix}-ingestion-stream"
  api_name              = "${local.resource_prefix}-ingestion-api"
  lambda_name           = "${local.resource_prefix}-etl"
  eventbridge_rule_name = "${local.resource_prefix}-s3-batch-ingestion"
}

resource "aws_kinesis_stream" "ingestion" {
  name             = local.stream_name
  retention_period = var.kinesis_retention_hours

  encryption_type = var.kinesis_encryption_type
  kms_key_id      = var.kinesis_encryption_type == "KMS" ? var.kinesis_kms_key_id : null

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = merge(
    var.tags,
    {
      Name        = local.stream_name
      Description = "Ingestion stream for real-time data"
    }
  )
}

resource "aws_apigatewayv2_api" "ingestion" {
  name          = local.api_name
  protocol_type = "HTTP"
  description   = "HTTP API for real-time data ingestion to Kinesis"

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

resource "aws_apigatewayv2_integration" "kinesis" {
  api_id              = aws_apigatewayv2_api.ingestion.id
  integration_type    = "AWS_PROXY"
  integration_subtype = "Kinesis-PutRecord"

  credentials_arn = aws_iam_role.api_gateway_kinesis.arn

  request_parameters = {
    StreamName   = aws_kinesis_stream.ingestion.name
    Data         = "$request.body"
    PartitionKey = "$request.header.X-Partition-Key"
  }

  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "ingest" {
  api_id    = aws_apigatewayv2_api.ingestion.id
  route_key = "POST /ingest"

  target = "integrations/${aws_apigatewayv2_integration.kinesis.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.ingestion.id
  name        = "$default"
  auto_deploy = true

  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []

    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn

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

data "archive_file" "etl_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/etl"
  output_path = "${path.module}/../../lambdas/etl/lambda_etl.zip"

  excludes = [
    "lambda_etl.zip",
    "__pycache__",
    "*.pyc",
    ".pytest_cache",
    "test_*.py",   # unit tests not needed at runtime
    "conftest.py", # pytest fixtures
    ".coverage"    # coverage DB (binary, changes every test run)
  ]
}

resource "aws_sqs_queue" "etl_dlq" {
  name = "${local.resource_prefix}-etl-dlq"

  message_retention_seconds = 1209600 # 14 days

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-etl-dlq"
      Description = "Dead letter queue for failed ETL Lambda processing"
      Purpose     = "ErrorHandling"
    }
  )
}

resource "aws_cloudwatch_log_group" "etl_lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.lambda_name}-logs"
      Description = "CloudWatch logs for ETL Lambda function"
    }
  )
}

resource "aws_lambda_function" "etl" {
  function_name = local.lambda_name
  description   = "ETL function: Kinesis to S3 raw layer with validation and normalization"

  filename         = data.archive_file.etl_lambda.output_path
  source_code_hash = data.archive_file.etl_lambda.output_base64sha256

  runtime     = "python3.11"
  handler     = "etl_handler.lambda_handler"
  timeout     = 60  # Kinesis batch window is 5s; 60s allows for S3 write latency + retries without approaching stream retention boundary
  memory_size = 256 # 256MB sufficient for JSON decode + S3 write; load test confirmed P95=2044ms well within timeout
  role        = aws_iam_role.etl_lambda.arn
  environment {
    variables = {
      DATA_LAKE_BUCKET = var.data_lake_bucket_name
      RAW_PREFIX       = "raw/"
      LOG_LEVEL        = "INFO"
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.etl_dlq.arn
  }

  # X-Ray active tracing: per-invocation latency timeline + downstream AWS SDK call segments
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

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

resource "aws_lambda_event_source_mapping" "kinesis_to_etl" {
  event_source_arn                   = aws_kinesis_stream.ingestion.arn
  function_name                      = aws_lambda_function.etl.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 1
  maximum_retry_attempts             = 3
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.etl_dlq.arn
    }
  }
  # bisect_batch_on_function_error not set â€” poison-pill protection handled by maximum_retry_attempts = 3 + DLQ
  depends_on = [
    aws_iam_role_policy_attachment.lambda_kinesis_execution,
    aws_lambda_function.etl
  ]
}

resource "aws_cloudwatch_event_rule" "s3_batch_ingestion" {
  name        = local.eventbridge_rule_name
  description = "Detects batch file uploads to raw/ layer for Step Functions processing"

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

resource "aws_cloudwatch_event_target" "step_functions" {
  count     = var.create_eventbridge_target ? 1 : 0
  rule      = aws_cloudwatch_event_rule.s3_batch_ingestion.name
  target_id = "StepFunctionsOrchestrator"
  arn       = var.state_machine_arn
  role_arn  = aws_iam_role.eventbridge_step_functions[0].arn
}
