# Repository Structure

## Root Directory Layout

```
AI-DP/
├── bootstrap/          # Terraform config for S3 state bucket creation (not yet implemented)
├── docs/              # Project documentation
├── envs/              # Environment-specific Terraform configurations
├── lambdas/           # Python Lambda function source code
├── modules/           # Reusable Terraform modules
├── .github/           # GitHub Actions workflows (not yet implemented)
├── .gitignore         # Git ignore patterns
├── .terraform-version # Terraform version constraint (1.13.0)
├── requirements.txt   # Empty root-level requirements
└── CLAUDE.md          # Claude Code guidance file
```

## Environments (`envs/`)

Three environment directories for deployment isolation:
- `envs/dev/` - Development environment
- `envs/stg/` - Staging environment  
- `envs/prod/` - Production environment

Each environment contains (when implemented):
- `backend.tf` - S3 backend configuration with native locking
- `providers.tf` - AWS provider configuration
- `main.tf` - Root module that wires together modules from `modules/`
- `variables.tf` - Environment-specific variable declarations
- `terraform.tfvars` - Environment-specific values (gitignored)

**Current status**: Directories exist but are empty.

## Terraform Modules (`modules/`)

Reusable infrastructure modules:

- **`data_lake/`**: S3 buckets with prefixes (raw/, processed/, curated/), lifecycle policies, encryption
- **`ingestion_stream/`**: API Gateway HTTP endpoint, Kinesis Data Streams, EventBridge rules for S3 events
- **`step_functions/`**: State machine orchestration, ASL definition, CloudWatch logging, retry logic
- **`ai_enrichment/`**: Comprehend integration, SageMaker endpoint, optional Rekognition (feature-flagged)
- **`hot_store/`**: DynamoDB tables, GSIs, TTL configuration
- **`analytics/`**: Glue crawler, Athena database/workgroup, optional QuickSight
- **`observability/`**: CloudWatch dashboards/alarms, X-Ray, SQS DLQs

**Current status**: Directories exist but are empty.

## Lambda Functions (`lambdas/`)

Python-based Lambda function code:

- **`lambdas/etl/`**: Kinesis consumer that validates, normalizes, and writes to S3 raw/
  - `app.py` - Main handler
  - `requirements.txt` - Python dependencies
  
- **`lambdas/merge/`**: Merges AI service outputs, writes to S3 processed/ and DynamoDB
  - `app.py` - Main handler
  - `requirements.txt` - Python dependencies

- **`lambdas/replay/`**: DLQ replay utility for reprocessing failed messages
  - `app.py` - Main handler
  - `requirements.txt` - Python dependencies

**Current status**: Directories exist but are empty.

## Documentation (`docs/`)

- `ai-dp overview notion.md` - Comprehensive architecture overview and project goals
- `coding-rules.md` - Development principles and coding standards (IMPORTANT: read before making changes)
- `error-rules.md` - Error tracking guidelines
- `errorlog.md` - Historical error log
- `roadmap.md` - Detailed implementation roadmap with phases and completion criteria
- `status.md` - Project status tracking

## Module Wiring Pattern

Each environment's `main.tf` instantiates modules and passes outputs between them:

```hcl
module "data_lake" {
  source = "../../modules/data_lake"
  # ... variables
}

module "ingestion_stream" {
  source         = "../../modules/ingestion_stream"
  raw_bucket_arn = module.data_lake.raw_bucket_arn  # Cross-module reference
  # ... other variables
}
```

Modules are designed to be reusable across environments with different tfvars configurations.