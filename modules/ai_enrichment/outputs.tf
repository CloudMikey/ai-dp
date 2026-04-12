#-------------------- AI Enrichment Module Outputs --------------------#

output "comprehend_policy_arn" {
  description = "ARN of the IAM policy granting Comprehend permissions"
  value       = aws_iam_policy.comprehend.arn
}

output "comprehend_policy_name" {
  description = "Name of the Comprehend IAM policy"
  value       = aws_iam_policy.comprehend.name
}
