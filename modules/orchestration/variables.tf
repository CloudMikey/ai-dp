variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Environment must be dev, stg, or prod"
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ai-dp"
}

variable "data_lake_bucket_name" {
  description = "S3 bucket name for data lake (from data_lake module)"
  type        = string
}

variable "data_lake_bucket_arn" {
  description = "S3 bucket ARN for IAM policies (from data_lake module)"
  type        = string
}

variable "processed_prefix" {
  description = "S3 prefix for processed data layer"
  type        = string
  default     = "processed/"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for hot store (from hot_store module)"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN for IAM policies (from hot_store module)"
  type        = string
}

variable "ttl_days" {
  description = "TTL in days for DynamoDB records (auto-delete after N days)"
  type        = number
  default     = 30

  validation {
    condition     = var.ttl_days > 0 && var.ttl_days <= 365
    error_message = "TTL must be between 1 and 365 days"
  }
}

variable "log_level" {
  description = "Lambda logging level (INFO, DEBUG, ERROR)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["INFO", "DEBUG", "ERROR"], var.log_level)
    error_message = "Log level must be INFO, DEBUG, or ERROR"
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Invalid log retention days (must be valid CloudWatch retention value)"
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray active tracing on the Lambda (per-invocation latency + downstream call timeline)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource-specific tags (merged with provider default_tags)"
  type        = map(string)
  default     = {}
}
