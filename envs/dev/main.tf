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

#-------------------- Step Functions Orchestration Module --------------------#
# State machine for batch data pipeline orchestration
# Phase 4: Minimal Pass state for EventBridge integration testing

module "step_functions" {
  source = "../../modules/step_functions"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # CloudWatch Logs configuration
  log_retention_days = 7     # 7 days for dev
  log_level          = "ALL" # Full logging for dev debugging

  tags = {
    Component = "Orchestration"
  }
}

#-------------------- Streaming Ingestion Module --------------------#
# API Gateway HTTP API + Kinesis Data Stream for real-time ingestion

module "ingestion_stream" {
  source = "../../modules/ingestion_stream"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # Data Lake integration (Lambda writes to S3)
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn

  # Step Functions integration (Phase 4: EventBridge → Step Functions)
  state_machine_arn         = module.step_functions.state_machine_arn
  create_eventbridge_target = true

  # Kinesis configuration (1 shard = 1 MB/sec write capacity)
  kinesis_shard_count     = 1
  kinesis_retention_hours = 24
  kinesis_encryption_type = "NONE" # Use KMS in production

  # API Gateway configuration
  enable_api_gateway_logging     = true
  api_gateway_log_retention_days = 7
  enable_cors                    = true
  cors_allow_origins             = ["*"] # Restrict in production

  tags = {
    Component = "Ingestion"
    DataFlow  = "Streaming"
  }
}