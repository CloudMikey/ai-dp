#-------------------- Module Variables --------------------#
# Input variables for the hot store module

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
  description = "AWS region for DynamoDB table"
  type        = string
}

#-------------------- Table Configuration --------------------#

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery (35-day retention for backups)"
  type        = bool
  default     = true # Enabled by default (disaster recovery best practice)
}

variable "enable_ttl" {
  description = "Enable TTL for automatic record expiration (cost optimization)"
  type        = bool
  default     = true
}

variable "ttl_days" {
  description = "Number of days before records expire (used by Merge Lambda to set expiresAt)"
  type        = number
  default     = 30
  validation {
    condition     = var.ttl_days > 0 && var.ttl_days <= 365
    error_message = "TTL days must be between 1 and 365."
  }
}

#-------------------- Tagging Variables --------------------#

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
