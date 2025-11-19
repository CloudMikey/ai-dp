#-------------------- IAM Resources for Ingestion Stream Module --------------------#
# This file contains all IAM roles and policies for:
# - API Gateway → Kinesis integration
# - Lambda ETL function execution
# - EventBridge → Step Functions integration

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
