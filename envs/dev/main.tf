#-------------------- Provider Configuration --------------------#

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "AI-DP"
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      CostCenter  = "Engineering"
    }
  }
}

#-------------------- Data Lake Module --------------------#
# Creates S3 bucket with raw, processed, and curated data layers

module "data_lake" {
  source = "../../modules/data_lake"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # Use SSE-S3 encryption for dev (KMS adds cost, use in prod if needed)
  kms_key_arn = null

  # Enable versioning for data protection
  enable_versioning = true

  # Dev environment: Shorter lifecycle for faster iteration and lower costs
  raw_layer_lifecycle = {
    transition_to_ia_days      = 30
    transition_to_glacier_days = 90
    expiration_days            = 180 # 6 months retention for dev
  }

  processed_layer_lifecycle = {
    transition_to_ia_days      = 60
    transition_to_glacier_days = 120
    expiration_days            = 365 # 1 year retention for dev
  }

  curated_layer_lifecycle = {
    transition_to_ia_days      = 0 # No transitions for frequently accessed data
    transition_to_glacier_days = 0
    expiration_days            = 0 # Keep indefinitely
  }
}
