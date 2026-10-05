variable "aws_region" {
  description = "AWS region for the S3 state bucket"
  type        = string
}

variable "project_name" {
  description = "Project name used for naming resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID (used for unique bucket naming)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "AWS Account ID must be a 12-digit number."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 state bucket"
  type        = bool
  default     = true
}

variable "enable_lifecycle_rules" {
  description = "Enable lifecycle rules for old versions"
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent versions are deleted"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags for the S3 bucket"
  type        = map(string)
  default     = {}
}

variable "bootstrap_s3" {
  description = "Name of the S3 bucket for bootstrap"
  type        = string
  default     = "tf-state-aidp"
}



