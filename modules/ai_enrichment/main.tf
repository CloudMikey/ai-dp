#============================================================#
#  AI Enrichment Module - AWS Comprehend Integration
#============================================================#
# This module provides IAM permissions for Step Functions to call
# AWS Comprehend services for sentiment analysis and entity detection.
# Comprehend is serverless, so no resources need to be provisioned.
#
# Portfolio Note: Demonstrates AWS AI service integration via
# Step Functions service orchestration pattern.
#============================================================#

terraform {
  required_version = ">= 1.11.0"
}

# No resources to create - Comprehend is serverless
# This module only provides IAM role outputs for use by Step Functions
