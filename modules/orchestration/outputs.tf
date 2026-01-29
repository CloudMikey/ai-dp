#-------------------- Orchestration Module Outputs --------------------#

output "lambda_function_arn" {
  description = "ARN of Merge Lambda function (for Step Functions invocation)"
  value       = aws_lambda_function.merge.arn
}

output "lambda_function_name" {
  description = "Name of Merge Lambda function"
  value       = aws_lambda_function.merge.function_name
}

output "lambda_role_arn" {
  description = "ARN of Lambda execution role"
  value       = aws_iam_role.merge_lambda.arn
}

output "dlq_url" {
  description = "URL of Dead Letter Queue for monitoring"
  value       = aws_sqs_queue.merge_dlq.url
}

output "dlq_arn" {
  description = "ARN of Dead Letter Queue"
  value       = aws_sqs_queue.merge_dlq.arn
}

output "dlq_name" {
  description = "Name of Dead Letter Queue (for CloudWatch metrics)"
  value       = aws_sqs_queue.merge_dlq.name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for Lambda logs"
  value       = aws_cloudwatch_log_group.merge_lambda.name
}
