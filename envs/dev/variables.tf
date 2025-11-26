#-------------------- Environment Variables --------------------#
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
