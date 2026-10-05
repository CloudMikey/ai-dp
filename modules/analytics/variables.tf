variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stg, prod"
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
}

variable "data_lake_bucket_name" {
  description = "Name of the S3 data lake bucket (for crawler target path)"
  type        = string
}

variable "data_lake_bucket_arn" {
  description = "ARN of the S3 data lake bucket (for IAM policies)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
