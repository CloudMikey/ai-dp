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
