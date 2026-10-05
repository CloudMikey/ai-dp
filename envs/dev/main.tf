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

# State machine for batch pipeline orchestration: invokes Comprehend enrichment then the merge Lambda

module "step_functions" {
  source = "../../modules/step_functions"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # AI Enrichment integration
  data_lake_bucket_arn  = module.data_lake.bucket_arn
  comprehend_policy_arn = module.ai_enrichment.comprehend_policy_arn

  # Final state invokes the merge Lambda to combine enrichment outputs
  merge_lambda_arn = module.orchestration.lambda_function_arn

  # CloudWatch Logs configuration
  log_retention_days = 7     # 7 days for dev
  log_level          = "ALL" # Full logging for dev debugging

  tags = {
    Component = "Orchestration"
  }
}

# AWS Comprehend integration for sentiment analysis and entity detection

module "ai_enrichment" {
  source = "../../modules/ai_enrichment"

  environment  = "dev"
  project_name = var.project_name
}

# Fast query store for AI-enriched data (recent records only)

module "hot_store" {
  source = "../../modules/hot_store"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # Dev configuration: Enable all features for learning/testing
  enable_point_in_time_recovery = true
  enable_ttl                    = true
  ttl_days                      = 30 # 30 days retention for dev

  tags = {
    Component = "Storage"
    DataType  = "Enriched"
  }
}

# Merge Lambda: Combines AI enrichment results and writes to S3 processed/ + DynamoDB

module "orchestration" {
  source = "../../modules/orchestration"

  environment  = "dev"
  project_name = var.project_name

  # Data Lake integration
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn
  processed_prefix      = "processed/"

  # DynamoDB Hot Store integration
  dynamodb_table_name = module.hot_store.table_name
  dynamodb_table_arn  = module.hot_store.table_arn
  ttl_days            = 30

  # Lambda configuration
  log_level           = "INFO"
  log_retention_days  = 7
  enable_xray_tracing = true

  tags = {
    Component = "Orchestration"
    Purpose   = "AIEnrichmentMerge"
  }
}

# API Gateway HTTP API + Kinesis Data Stream for real-time ingestion

module "ingestion_stream" {
  source = "../../modules/ingestion_stream"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # Data Lake integration (Lambda writes to S3)
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn

  # EventBridge rule on S3 object-created events triggers the Step Functions state machine
  state_machine_arn         = module.step_functions.state_machine_arn
  create_eventbridge_target = true

  # Kinesis: provisioned 1-shard for steady low-volume dev traffic (cost-optimized vs on-demand)
  kinesis_stream_mode     = "PROVISIONED"
  kinesis_shard_count     = 1
  kinesis_retention_hours = 24
  kinesis_encryption_type = "KMS"               # Encrypt data at rest in the stream
  kinesis_kms_key_id      = "alias/aws/kinesis" # AWS-managed key (no additional cost)

  # API Gateway configuration
  enable_api_gateway_logging     = true
  api_gateway_log_retention_days = 7
  enable_cors                    = true
  cors_allow_origins             = ["*"] # Restrict in production

  enable_xray_tracing = true

  tags = {
    Component = "Ingestion"
    DataFlow  = "Streaming"
  }
}

# AWS Glue Data Catalog + Athena for SQL queries on enriched data

module "analytics" {
  source = "../../modules/analytics"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # Data Lake integration (crawler reads from processed/ prefix)
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn

  tags = {
    Component = "Analytics"
    Purpose   = "DataCatalogAndQueries"
  }
}

# CloudWatch operational dashboard for pipeline health monitoring

module "observability" {
  source = "../../modules/observability"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  # Lambda functions
  etl_lambda_function_name   = module.ingestion_stream.lambda_function_name
  merge_lambda_function_name = module.orchestration.lambda_function_name

  # Kinesis stream
  kinesis_stream_name = module.ingestion_stream.kinesis_stream_name

  # Step Functions
  state_machine_name = module.step_functions.state_machine_name
  state_machine_arn  = module.step_functions.state_machine_arn

  # DynamoDB
  dynamodb_table_name = module.hot_store.table_name

  # Dead Letter Queue (streaming path; batch failures surface as Step Functions failures)
  etl_dlq_name = module.ingestion_stream.dlq_name

  # SNS email notifications for the 5 operational alarms
  alarm_notification_emails = [var.alarm_email]

  tags = {
    Component = "Observability"
    Purpose   = "OperationalDashboard"
  }
}

# AWS Budgets for cost monitoring and alerting

module "cost_management" {
  source = "../../modules/cost_management"

  environment  = "dev"
  project_name = var.project_name

  # Budget configuration
  budget_amount       = "50.00"
  time_period_start   = "2026-01-01_00:00"
  notification_emails = [var.alarm_email] # Reuse alarm email for budget alerts

  tags = {
    Component = "CostManagement"
  }
}


