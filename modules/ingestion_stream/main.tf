#-------------------- Streaming Ingestion Module --------------------#
# Creates API Gateway HTTP API and Kinesis Data Stream for real-time data ingestion
# Direct integration (no Lambda proxy) reduces latency and cost
# API Gateway → Kinesis → (later) Lambda ETL → S3

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  stream_name     = "${local.resource_prefix}-ingestion-stream"
  api_name        = "${local.resource_prefix}-ingestion-api"
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

# Trust policy: Allow API Gateway to assume this role
data "aws_iam_policy_document" "api_gateway_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM role for API Gateway
resource "aws_iam_role" "api_gateway_kinesis" {
  name               = "${local.resource_prefix}-apigw-kinesis-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role.json

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-apigw-kinesis-role"
      Description = "Allows API Gateway to write to Kinesis stream"
    }
  )
}

# Permissions policy: Allow PutRecord to Kinesis stream
data "aws_iam_policy_document" "api_gateway_kinesis_policy" {
  statement {
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords"
    ]

    # Least privilege: Only allow writes to this specific stream
    resources = [aws_kinesis_stream.ingestion.arn]
  }
}

# Attach policy to role
resource "aws_iam_role_policy" "api_gateway_kinesis" {
  name   = "kinesis-put-record"
  role   = aws_iam_role.api_gateway_kinesis.id
  policy = data.aws_iam_policy_document.api_gateway_kinesis_policy.json
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
