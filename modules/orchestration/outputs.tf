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

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for Lambda logs"
  value       = aws_cloudwatch_log_group.merge_lambda.name
}



