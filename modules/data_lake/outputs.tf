# Exports bucket information for use by other modules (ingestion, processing, analytics)

output "bucket_name" {
  description = "Name of the data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.id
}

output "bucket_arn" {
  description = "ARN of the data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.arn
}

output "bucket_id" {
  description = "ID of the data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.id
}

output "bucket_domain_name" {
  description = "Domain name of the data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.bucket_regional_domain_name
}

# Provides the prefix paths for each data layer

output "raw_prefix" {
  description = "S3 prefix for raw data layer"
  value       = "raw/"
}

output "processed_prefix" {
  description = "S3 prefix for processed (AI-enriched) data layer"
  value       = "processed/"
}

output "curated_prefix" {
  description = "S3 prefix for curated (business-ready) data layer"
  value       = "curated/"
}

# Convenience outputs for full S3 paths

output "raw_bucket_path" {
  description = "Full S3 path to raw data layer"
  value       = "s3://${aws_s3_bucket.data_lake.id}/raw/"
}

output "processed_bucket_path" {
  description = "Full S3 path to processed data layer"
  value       = "s3://${aws_s3_bucket.data_lake.id}/processed/"
}

output "curated_bucket_path" {
  description = "Full S3 path to curated data layer"
  value       = "s3://${aws_s3_bucket.data_lake.id}/curated/"
}

output "versioning_enabled" {
  description = "Whether bucket versioning is enabled"
  value       = var.enable_versioning
}

output "encryption_type" {
  description = "Type of encryption used (AES256 or KMS)"
  value       = var.kms_key_arn != null ? "KMS" : "AES256"
}

output "eventbridge_enabled" {
  description = "Whether EventBridge notifications are enabled for the bucket"
  value       = true
}
