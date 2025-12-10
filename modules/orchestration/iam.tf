#-------------------- IAM Resources for Merge Lambda --------------------#

#-------------------- Lambda Execution Role --------------------#
# Allows Lambda service to assume this role

resource "aws_iam_role" "merge_lambda" {
  name = "${local.resource_prefix}-merge-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.resource_prefix}-merge-lambda-role"
      Description = "Execution role for Merge Lambda"
    }
  )
}

#-------------------- S3 Write Policy --------------------#
# Least-privilege: Lambda can ONLY write to processed/* prefix

resource "aws_iam_role_policy" "s3_write" {
  name = "${local.resource_prefix}-merge-s3-write"
  role = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${var.data_lake_bucket_arn}/processed/*"
      }
    ]
  })
}

#-------------------- DynamoDB Write Policy --------------------#
# Least-privilege: Lambda can ONLY write items (no read/scan/delete)

resource "aws_iam_role_policy" "dynamodb_write" {
  name = "${local.resource_prefix}-merge-dynamodb-write"
  role = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

#-------------------- CloudWatch Logs Policy --------------------#
# Standard Lambda logging permissions

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.merge_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#-------------------- SQS DLQ Write Policy --------------------#
# Allows Lambda to send failed invocations to DLQ

resource "aws_iam_role_policy" "dlq_write" {
  name = "${local.resource_prefix}-merge-dlq-write"
  role = aws_iam_role.merge_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.merge_dlq.arn
      }
    ]
  })
}
