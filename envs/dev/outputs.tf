#-------------------- Dev Environment Outputs --------------------#

#-------------------- Data Lake Outputs --------------------#

output "data_lake_bucket_name" {
  description = "Name of the data lake S3 bucket"
  value       = module.data_lake.bucket_name
}

output "data_lake_bucket_arn" {
  description = "ARN of the data lake S3 bucket"
  value       = module.data_lake.bucket_arn
}

output "data_lake_raw_path" {
  description = "Full S3 path to raw data layer"
  value       = module.data_lake.raw_bucket_path
}

output "data_lake_processed_path" {
  description = "Full S3 path to processed data layer"
  value       = module.data_lake.processed_bucket_path
}

output "data_lake_curated_path" {
  description = "Full S3 path to curated data layer"
  value       = module.data_lake.curated_bucket_path
}

#-------------------- Streaming Ingestion Outputs --------------------#

output "api_gateway_invoke_url" {
  description = "API Gateway endpoint URL for data ingestion (use this for testing)"
  value       = module.ingestion_stream.api_gateway_invoke_url
}

output "api_gateway_id" {
  description = "API Gateway HTTP API ID"
  value       = module.ingestion_stream.api_gateway_id
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis ingestion stream"
  value       = module.ingestion_stream.kinesis_stream_name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis ingestion stream"
  value       = module.ingestion_stream.kinesis_stream_arn
}
