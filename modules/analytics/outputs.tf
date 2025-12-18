#-------------------- Glue Data Catalog Outputs --------------------#

output "database_name" {
  description = "Name of the Glue Data Catalog database"
  value       = aws_glue_catalog_database.analytics.name
}

output "database_id" {
  description = "ID of the Glue Data Catalog database"
  value       = aws_glue_catalog_database.analytics.id
}

#-------------------- Glue Crawler Outputs --------------------#

output "crawler_name" {
  description = "Name of the Glue Crawler"
  value       = aws_glue_crawler.processed_data.name
}

output "crawler_arn" {
  description = "ARN of the Glue Crawler"
  value       = aws_glue_crawler.processed_data.arn
}

#-------------------- Athena Workgroup Outputs --------------------#

output "workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.dev.name
}

output "workgroup_id" {
  description = "ID of the Athena workgroup"
  value       = aws_athena_workgroup.dev.id
}

output "workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.dev.arn
}

#-------------------- S3 Athena Results Outputs --------------------#

output "athena_results_bucket" {
  description = "Name of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_results_bucket_arn" {
  description = "ARN of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.arn
}

#-------------------- Helper Outputs for Dashboard --------------------#

output "table_name" {
  description = "Expected table name created by the crawler (note: only exists after crawler runs)"
  value       = "processed"
}

output "athena_query_result_location" {
  description = "S3 location where Athena query results are stored"
  value       = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
}
