#-------------------- AI Enrichment Module --------------------#
# Comprehend is serverless — this module only provisions IAM permissions.
# No compute resources needed; Step Functions calls Comprehend directly.

terraform {
  required_version = ">= 1.11.0"
}

# No resources to create - Comprehend is serverless
# This module only provides IAM role outputs for use by Step Functions
