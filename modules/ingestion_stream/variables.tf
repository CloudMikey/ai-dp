#-------------------- Module Variables --------------------#
# Input variables for the streaming ingestion module
# Configures API Gateway HTTP API and Kinesis Data Stream for real-time data ingestion

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Environment must be dev, stg, or prod."
  }
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

#-------------------- Kinesis Configuration --------------------#

variable "kinesis_retention_hours" {
  description = "Data retention period in hours (24-8760). Default 24 hours balances cost and debugging time."
  type        = number
  default     = 24
  validation {
    condition     = var.kinesis_retention_hours >= 24 && var.kinesis_retention_hours <= 8760
    error_message = "Retention hours must be between 24 and 8760 (1 year)."
  }
}

variable "kinesis_encryption_type" {
  description = "Encryption type for Kinesis stream. NONE (default, no cost) or KMS (additional cost)."
  type        = string
  default     = "NONE"
  validation {
    condition     = contains(["NONE", "KMS"], var.kinesis_encryption_type)
    error_message = "Encryption type must be NONE or KMS."
  }
}

variable "kinesis_kms_key_id" {
  description = "KMS key ID for Kinesis encryption. Required if kinesis_encryption_type is KMS."
  type        = string
  default     = null
}

#-------------------- API Gateway Configuration --------------------#

variable "enable_api_gateway_logging" {
  description = "Enable CloudWatch logging for API Gateway. Useful for dev/debugging, adds CloudWatch costs."
  type        = bool
  default     = true
}

variable "api_gateway_log_retention_days" {
  description = "CloudWatch log retention period for API Gateway logs (days)"
  type        = number
  default     = 7
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.api_gateway_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "enable_cors" {
  description = "Enable CORS for API Gateway. Useful for dev/testing with web clients."
  type        = bool
  default     = true
}

variable "cors_allow_origins" {
  description = "List of allowed CORS origins. Use ['*'] for dev, specific domains for prod."
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "List of allowed CORS HTTP methods"
  type        = list(string)
  default     = ["POST", "OPTIONS"]
}

#-------------------- Data Lake Integration --------------------#

variable "data_lake_bucket_name" {
  description = "Name of the S3 data lake bucket (for Lambda environment variable)"
  type        = string
}

variable "data_lake_bucket_arn" {
  description = "ARN of the S3 data lake bucket (for IAM policies)"
  type        = string
}

#-------------------- Tagging Variables --------------------#

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

#-------------------- Step Functions Integration (Phase 4) --------------------#

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine for batch ingestion orchestration (from step_functions module)"
  type        = string
  default     = ""
}

variable "create_eventbridge_target" {
  description = "Create EventBridge target to invoke Step Functions. Set to true after Step Functions module is deployed (Phase 4, Task 3)."
  type        = bool
  default     = false
}
