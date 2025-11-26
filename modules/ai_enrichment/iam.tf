#============================================================#
#  IAM Policies for Step Functions → Comprehend
#============================================================#

#-------------------- Comprehend Policy Document --------------------#
# Allows Step Functions to call Comprehend sentiment and entity detection
data "aws_iam_policy_document" "comprehend_policy" {
  # Sentiment analysis permission
  statement {
    sid    = "AllowComprehendSentiment"
    effect = "Allow"
    actions = [
      "comprehend:DetectSentiment"
    ]
    resources = ["*"] # Comprehend APIs don't use resource-level permissions
  }

  # Entity detection permission
  statement {
    sid    = "AllowComprehendEntities"
    effect = "Allow"
    actions = [
      "comprehend:DetectEntities"
    ]
    resources = ["*"]
  }
}

#-------------------- IAM Policy Resource --------------------#
# Creates the policy that can be attached to Step Functions execution role
resource "aws_iam_policy" "comprehend" {
  name        = "${var.environment}-${var.project_name}-comprehend-policy"
  description = "Allows Step Functions to call AWS Comprehend for AI enrichment"
  policy      = data.aws_iam_policy_document.comprehend_policy.json

  tags = {
    Name = "${var.environment}-${var.project_name}-comprehend-policy"
  }
}
