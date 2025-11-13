#-------------------- Module Variables --------------------#

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

#-------------------- Logging Configuration --------------------#

variable "log_retention_days" {
  description = "CloudWatch log retention period for Step Functions execution logs (days)"
  type        = number
  default     = 7
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "log_level" {
  description = "CloudWatch Logs level for Step Functions (ALL, ERROR, FATAL, OFF)"
  type        = string
  default     = "ALL"
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.log_level)
    error_message = "Log level must be ALL, ERROR, FATAL, or OFF."
  }
}

#-------------------- Tagging Variables --------------------#

variable "tags" {
  description = "Additional tags to apply to resources (merged with resource-specific tags)"
  type        = map(string)
  default     = {}
}
