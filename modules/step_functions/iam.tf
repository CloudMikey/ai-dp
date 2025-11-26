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

#-------------------- IAM Policy for S3 Read Access --------------------#
# Allows Step Functions to read objects from data lake (for AI enrichment)
# Scoped to raw/ prefix where batch ingestion uploads files

resource "aws_iam_role_policy" "step_functions_s3_read" {
  name = "s3-read-access"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${var.data_lake_bucket_arn}/raw/*"
      }
    ]
  })
}

#-------------------- Attach Comprehend Policy --------------------#
# Attaches AI enrichment policy for sentiment/entity detection

resource "aws_iam_role_policy_attachment" "comprehend" {
  role       = aws_iam_role.step_functions.name
  policy_arn = var.comprehend_policy_arn
}
