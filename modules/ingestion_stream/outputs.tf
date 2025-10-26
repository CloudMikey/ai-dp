#-------------------- Kinesis Stream Outputs --------------------#
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

#-------------------- API Gateway Outputs --------------------#
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

#-------------------- Configuration Outputs --------------------#

output "kinesis_shard_count" {
  description = "Number of shards configured for the Kinesis stream"
  value       = var.kinesis_shard_count
}

output "kinesis_retention_hours" {
  description = "Data retention period configured for the Kinesis stream (hours)"
  value       = var.kinesis_retention_hours
}
