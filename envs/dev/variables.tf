# Variables for the dev environment configuration

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "ai-dp"
}

variable "enable_github_oidc" {
  description = "Create the GitHub Actions deploy role (requires an existing GitHub OIDC provider in the account)"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}



