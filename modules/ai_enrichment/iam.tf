# Allows Step Functions to call Comprehend sentiment and entity detection
resource "aws_iam_policy" "comprehend" {
  name        = "${var.environment}-${var.project_name}-comprehend-policy"
  description = "Allows Step Functions to call AWS Comprehend for AI enrichment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowComprehendSentiment"
        Effect = "Allow"
        Action = [
          "comprehend:DetectSentiment"
        ]
        Resource = "*" # Comprehend APIs don't use resource-level permissions
      },
      {
        Sid    = "AllowComprehendEntities"
        Effect = "Allow"
        Action = [
          "comprehend:DetectEntities"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-${var.project_name}-comprehend-policy"
  }
}
