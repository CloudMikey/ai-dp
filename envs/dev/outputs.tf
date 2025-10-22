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
