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
  description = "AWS region for CloudWatch dashboard"
  type        = string
}

variable "etl_lambda_function_name" {
  description = "Name of the ETL Lambda function"
  type        = string
}

variable "merge_lambda_function_name" {
  description = "Name of the Merge Lambda function"
  type        = string
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis data stream"
  type        = string
}

variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine (used for CloudWatch metric dimensions)"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "etl_dlq_name" {
  description = "Name of the ETL Dead Letter Queue"
  type        = string
}

variable "alarm_notification_emails" {
  description = "List of email addresses to receive CloudWatch alarm notifications"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.alarm_notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All alarm notification emails must be valid email addresses."
  }
}

variable "lambda_error_rate_threshold" {
  description = "Lambda error rate threshold (percentage)"
  type        = number
  default     = 5

  validation {
    condition     = var.lambda_error_rate_threshold >= 0 && var.lambda_error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100."
  }
}

variable "dlq_depth_threshold" {
  description = "DLQ message count threshold. Default 0 = alert on ANY message"
  type        = number
  default     = 0

  validation {
    condition     = var.dlq_depth_threshold >= 0
    error_message = "DLQ depth threshold must be >= 0."
  }
}

variable "kinesis_iterator_age_threshold_ms" {
  description = "Kinesis iterator age threshold in milliseconds"
  type        = number
  default     = 60000

  validation {
    condition     = var.kinesis_iterator_age_threshold_ms > 0
    error_message = "Kinesis iterator age threshold must be > 0."
  }
}

variable "step_functions_failure_threshold" {
  description = "Step Functions failure count threshold within evaluation period"
  type        = number
  default     = 3

  validation {
    condition     = var.step_functions_failure_threshold > 0
    error_message = "Step Functions failure threshold must be > 0."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
