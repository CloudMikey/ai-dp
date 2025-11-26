#============================================================#
#  AI Enrichment Module Variables
#============================================================#

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}
