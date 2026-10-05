# Execution role for Step Functions orchestrator (reads S3, invokes Comprehend + Merge Lambda)

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

# CloudWatch Logs delivery setup (wildcard required by AWS for log group setup)

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
        # SECURITY NOTE: Wildcard required by AWS for Step Functions logging
        # AWS does not support resource-level permissions for log delivery setup
        # Ref: https://docs.aws.amazon.com/step-functions/latest/dg/cw-logs.html
        Resource = "*"
      }
    ]
  })
}

# S3 read from raw/ prefix (batch ingestion entry point for AI enrichment)

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

# Comprehend permissions for DetectSentiment + DetectEntities (managed policy from module variable)

resource "aws_iam_role_policy_attachment" "comprehend" {
  role       = aws_iam_role.step_functions.name
  policy_arn = var.comprehend_policy_arn
}

# Invoke Merge Lambda after Comprehend analysis (to write enriched data)

resource "aws_iam_role_policy" "step_functions_lambda_invoke" {
  name = "lambda-invoke"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = var.merge_lambda_arn
      }
    ]
  })
}
