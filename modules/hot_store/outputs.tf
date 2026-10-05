output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.enriched_data.name
}

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.enriched_data.arn
}

output "table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.enriched_data.id
}

output "gsi_name" {
  description = "Name of the timestamp-based GSI"
  value       = "timestamp-index"
}

output "ttl_attribute_name" {
  description = "Name of the TTL attribute (for Merge Lambda reference)"
  value       = "expiresAt"
}

output "ttl_days" {
  description = "Number of days before TTL expiration (for Merge Lambda calculation)"
  value       = var.ttl_days
}



