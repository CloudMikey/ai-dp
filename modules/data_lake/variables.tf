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
  description = "AWS region for the data lake"
  type        = string
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for bucket encryption. If not provided, uses SSE-S3"
  type        = string
  default     = null
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
}

variable "raw_layer_lifecycle" {
  description = "Lifecycle configuration for raw data layer"
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
    expiration_days            = number
  })
  default = {
    transition_to_ia_days      = 30
    transition_to_glacier_days = 90
    expiration_days            = 365
  }
}

variable "processed_layer_lifecycle" {
  description = "Lifecycle configuration for processed data layer"
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
    expiration_days            = number
  })
  default = {
    transition_to_ia_days      = 60
    transition_to_glacier_days = 180
    expiration_days            = 730
  }
}

variable "curated_layer_lifecycle" {
  description = "Lifecycle configuration for curated data layer (frequently accessed, no transitions by default)"
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
    expiration_days            = number
  })
  default = {
    transition_to_ia_days      = 0 # 0 means disabled
    transition_to_glacier_days = 0 # 0 means disabled
    expiration_days            = 0 # 0 means disabled
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
