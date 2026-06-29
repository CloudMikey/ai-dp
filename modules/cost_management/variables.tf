variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = string
  default     = "50.00"
}

variable "time_period_start" {
  description = "Start date for budget tracking (YYYY-MM-DD_HH:MM format)"
  type        = string
  default     = "2026-01-01_00:00"
}

variable "notification_emails" {
  description = "List of email addresses for budget alerts"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
