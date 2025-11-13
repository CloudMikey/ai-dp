#-------------------- Step Functions Orchestration Module --------------------#
# Minimal state machine with Pass state for EventBridge integration testing
# Phase 4: Validates end-to-end batch ingestion path (S3 → EventBridge → Step Functions)
# Phase 5+: Expand to parallel Lambda tasks for AI enrichment

locals {
  resource_prefix    = "${var.project_name}-${var.environment}"
  state_machine_name = "${local.resource_prefix}-orchestrator"
}

#-------------------- CloudWatch Log Group --------------------#
# Stores Step Functions execution logs for debugging
# Created before state machine to ensure logs are captured from first execution
# Retention: 7 days for dev (increase for prod to meet compliance requirements)

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${local.state_machine_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${local.state_machine_name}-logs"
      Description = "Step Functions execution logs"
    }
  )
}

#-------------------- IAM Role for Step Functions --------------------#
# Execution role for state machine
# Trust policy: Allow Step Functions service to assume role
# Permissions: CloudWatch Logs only (Pass state doesn't invoke external services)

resource "aws_iam_role" "step_functions" {
  name = "${local.resource_prefix}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-step-functions-role"
      Description = "Execution role for Step Functions orchestrator"
    }
  )
}

#-------------------- IAM Policy for CloudWatch Logs --------------------#
# Permissions for Step Functions to write execution logs to CloudWatch
# Required actions for log delivery setup and management

resource "aws_iam_role_policy" "step_functions_logging" {
  name = "cloudwatch-logs"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*" # Required for Step Functions logging setup
      }
    ]
  })
}

#-------------------- Step Functions State Machine --------------------#
# Minimal Pass state for Phase 4 EventBridge integration testing
# Accepts S3 event from EventBridge, returns success message
# Future: Replace Pass state with Parallel tasks for AI enrichment (Phase 5+)

resource "aws_sfn_state_machine" "orchestrator" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions.arn

  # ASL definition: Minimal Pass state for integration testing
  # Pass state doesn't invoke services, just validates event delivery
  definition = jsonencode({
    Comment = "Phase 4: Minimal orchestration - validates EventBridge integration"
    StartAt = "ReceiveEvent"
    States = {
      ReceiveEvent = {
        Type    = "Pass"
        Comment = "Placeholder state - accepts S3 event, no processing yet"
        Result = {
          message    = "Event received successfully"
          phase      = "4-complete"
          next_steps = "Add Lambda tasks in Phase 5"
        }
        ResultPath = "$.processing_result"
        End        = true
      }
    }
  })

  # CloudWatch Logs configuration - log level ALL for dev visibility
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = var.log_level
  }

  # Ensure dependencies are created first
  depends_on = [
    aws_cloudwatch_log_group.step_functions,
    aws_iam_role_policy.step_functions_logging
  ]

  tags = merge(
    var.tags,
    {
      Name        = local.state_machine_name
      Description = "Orchestrates batch data pipeline execution"
      Component   = "Orchestration"
    }
  )
}
