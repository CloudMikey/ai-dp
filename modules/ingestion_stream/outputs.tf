# Exports Kinesis stream information for Lambda event source mapping

output "kinesis_stream_name" {
  description = "Name of the Kinesis data stream"
  value       = aws_kinesis_stream.ingestion.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis data stream (for IAM policies and Lambda event source)"
  value       = aws_kinesis_stream.ingestion.arn
}

output "kinesis_stream_id" {
  description = "ID of the Kinesis data stream"
  value       = aws_kinesis_stream.ingestion.id
}

# Exports API Gateway endpoint information for testing and integration

output "api_gateway_id" {
  description = "ID of the API Gateway HTTP API"
  value       = aws_apigatewayv2_api.ingestion.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway HTTP API"
  value       = aws_apigatewayv2_api.ingestion.arn
}

output "api_gateway_endpoint_url" {
  description = "Full URL of the API Gateway endpoint (for testing and client integration)"
  value       = aws_apigatewayv2_api.ingestion.api_endpoint
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway stage (includes /ingest route)"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/ingest"
}

output "kinesis_retention_hours" {
  description = "Data retention period configured for the Kinesis stream (hours)"
  value       = var.kinesis_retention_hours
}

output "lambda_function_name" {
  description = "Name of the ETL Lambda function"
  value       = aws_lambda_function.etl.function_name
}

output "lambda_function_arn" {
  description = "ARN of the ETL Lambda function"
  value       = aws_lambda_function.etl.arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.etl.version
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.etl_lambda.arn
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue for failed Lambda invocations"
  value       = aws_sqs_queue.etl_dlq.url
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.etl_dlq.arn
}

output "dlq_name" {
  description = "Name of the Dead Letter Queue (for CloudWatch metrics)"
  value       = aws_sqs_queue.etl_dlq.name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for batch ingestion detection"
  value       = aws_cloudwatch_event_rule.s3_batch_ingestion.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule that triggers Step Functions on S3 batch uploads"
  value       = aws_cloudwatch_event_rule.s3_batch_ingestion.arn
}

output "eventbridge_target_created" {
  description = "Whether EventBridge target to Step Functions was created"
  value       = var.create_eventbridge_target
}

output "eventbridge_sfn_role_arn" {
  description = "ARN of the IAM role for EventBridge to Step Functions invocation (if created)"
  value       = var.create_eventbridge_target ? aws_iam_role.eventbridge_step_functions[0].arn : null
}
