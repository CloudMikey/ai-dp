#-------------------- IAM Resources for Step Functions Module --------------------#
# This file contains all IAM roles and policies for:
# - Step Functions state machine execution
# - CloudWatch Logs permissions

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
