# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **AI-Powered Serverless Data Pipeline** built on AWS infrastructure managed with Terraform. The pipeline ingests both batch and streaming data, enriches it with AWS AI services (Comprehend, SageMaker), and provides analytics through a dual storage strategy (DynamoDB for hot data, S3 Data Lake for historical queries).

**Key Technologies:**
- Infrastructure: Terraform >= 1.11.0 with S3 backend (native locking via `use_lockfile = true`)
- Compute: AWS Lambda, Step Functions, EventBridge
- Data Ingestion: API Gateway → Kinesis Data Streams, S3 batch uploads
- AI/ML: Amazon Comprehend, SageMaker real-time endpoints, (optional) Rekognition
- Storage: S3 (raw/processed/curated layers), DynamoDB, Glue + Athena
- Observability: CloudWatch, X-Ray, SQS DLQs

## Repository Structure

```
AI-DP/
├── bootstrap/          # (Future) Terraform config for creating S3 state bucket
├── envs/               # Environment-specific Terraform configs
│   ├── dev/           # Development environment
│   ├── stg/           # Staging environment
│   └── prod/          # Production environment
├── modules/           # Reusable Terraform modules
│   ├── data_lake/            # S3 buckets (raw/processed/curated)
│   ├── ingestion_stream/     # API Gateway, Kinesis, EventBridge
│   ├── step_functions/       # Orchestration state machine
│   ├── ai_enrichment/        # Comprehend, Rekognition, SageMaker
│   ├── hot_store/            # DynamoDB tables
│   ├── analytics/            # Glue crawler, Athena
│   └── observability/        # CloudWatch dashboards, alarms, DLQs
├── lambdas/           # Python Lambda function code
│   ├── etl/          # Kinesis consumer (normalize & write to S3 raw)
│   ├── merge/        # Merge AI outputs, write to processed & DynamoDB
│   └── replay/       # DLQ replay utility
└── docs/             # Project documentation
```

## Architecture Pattern

**Data Flow:**
1. **Ingestion**: API Gateway → Kinesis OR S3 batch upload → EventBridge
2. **ETL**: Lambda consumes Kinesis → validates/normalizes → writes to S3 `raw/`
3. **Orchestration**: Step Functions fan-out to parallel AI enrichment tasks
4. **AI Enrichment**: Comprehend (sentiment, entities) + SageMaker (anomaly detection) + optional Rekognition
5. **Merge**: Lambda combines AI outputs → writes to S3 `processed/` + DynamoDB hot store
6. **Analytics**: Glue crawler catalogs data → Athena queries → QuickSight/React dashboards

**Error Handling**: All Lambdas use SQS DLQs, CloudWatch alarms monitor DLQ depth, replay Lambda processes failed messages.

## Development Commands

### Terraform Workflow

**Initialize environment:**
```powershell
terraform -chdir=envs/dev init
```

**Validate and format:**
```powershell
terraform -chdir=envs/dev fmt
terraform -chdir=envs/dev validate
```

**Plan changes:**
```powershell
terraform -chdir=envs/dev plan
```

**Apply changes:**
```powershell
terraform -chdir=envs/dev apply
```

**Destroy resources (use with caution):**
```powershell
terraform -chdir=envs/dev destroy
```

### Python Lambda Development

**Install dependencies:**
```powershell
cd lambdas/etl
pip install -r requirements.txt
```

**Run tests (when implemented):**
```powershell
pytest lambdas/etl/
```

## Coding Standards & Principles

### Fundamental Development Principles
**Always display these at the start of responses when making code changes:**
1. **NO HARDCODING**: All solutions must be generic and pattern-based
2. **ROOT CAUSE, NOT BANDAID**: Fix underlying structural issues, not symptoms
3. **DATA INTEGRITY**: Use consistent, authoritative data sources
4. **ASK QUESTIONS BEFORE CHANGING CODE**: Clarify requirements before implementing
5. **SECURITY-FIRST**: Use GitHub OIDC with short-lived tokens, never long-term credentials

### Code Quality
- Prefer simple solutions over complex ones
- Avoid code duplication—check for existing similar functionality first
- Keep files under 200-300 lines; refactor when approaching this limit
- Only make changes that are requested or directly related to the request
- Exhaust existing implementation options before introducing new patterns
- When introducing new patterns, remove old implementations to avoid duplicate logic

### Terraform Style
- Use decorative comment headers to separate resource groups:
  ```hcl
  #-------------------- DynamoDB Table --------------------#
  ```
- Add descriptive comments above each resource explaining its purpose
- Use single-line comments for complex configurations
- Maintain consistent spacing around comment blocks
- Always use up-to-date Terraform resources

### Environment & Security
- Write code that accounts for different environments: dev, stg, prod
- Never overwrite `.env` files without asking first
- Mock data only for tests, never for dev or prod
- **Environment Isolation**: Maintain strict separation between dev/staging/prod (ideally separate AWS accounts)
- **Zero-Trust**: All AWS access via short-lived tokens and least-privilege IAM roles

### Error Handling
- Review and update `docs/errorlog.md` when encountering errors
- Document: error message, attempted solutions, working fix
- Reference error log before attempting similar fixes

## Infrastructure Design Patterns

### Terraform Backend Configuration
This project uses **Terraform >= 1.11.0** with S3 native state locking (`use_lockfile = true`), eliminating the need for DynamoDB lock tables.

Example `backend.tf`:
```hcl
terraform {
  required_version = ">= 1.11.0"
  
  backend "s3" {
    bucket       = "tf-state-<account>-<region>"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-west-1"
    encrypt      = true
    use_lockfile = true  # Native S3 locking, no DynamoDB needed
  }
}
```

### Module Wiring Pattern
Root `main.tf` files in `envs/{dev,stg,prod}/` wire together modules from `modules/`. Modules pass outputs between each other (e.g., `data_lake.raw_bucket_arn` → `ingestion_stream` module).

### Feature Flags
Use Terraform variables for feature toggles:
- `feature_rekognition_on`: Enable/disable image labeling
- `create_quicksight`: Enable/disable QuickSight dashboard creation

## GitHub Actions CI/CD (Planned)

**CI Workflow** (on PRs):
- Terraform fmt/validate/plan
- tflint, tfsec security scanning

**Deploy Workflow** (on main branch):
- OIDC authentication (no long-term credentials)
- Environment promotion: dev → stg → prod
- Manual approval gates between environments

## Common Tasks

### Adding a New Terraform Module
1. Create directory under `modules/<module_name>/`
2. Add `main.tf`, `variables.tf`, `outputs.tf`
3. Wire module into environment-specific `main.tf` files
4. Update this CLAUDE.md if the module represents a new architectural component

### Adding a New Lambda Function
1. Create directory under `lambdas/<function_name>/`
2. Add `app.py` and `requirements.txt`
3. Create corresponding Lambda resource in appropriate Terraform module
4. Configure IAM role with least-privilege permissions
5. Add CloudWatch log group and error alarm
6. Configure SQS DLQ for error handling

### Modifying the Step Functions State Machine
1. Edit `modules/step_functions/statemachine.asl.json` (ASL format)
2. Update IAM role permissions if calling new services
3. Test locally with Step Functions Local or in dev environment
4. Update documentation if adding new orchestration paths

## Current Project Status

### Completed (Phase 0) ✅
**Bootstrap Infrastructure**
- S3 state bucket created: `tf-state-aidp`
- Backend configurations created for all environments (dev, stg, prod)
- All three environments initialized with S3 backend
- Backend uses Terraform 1.13.0 with native S3 locking (`use_lockfile = true`)

### Backend Configuration Details
- **Bucket**: `tf-state-aidp`
- **Region**: `us-west-1`
- **Encryption**: Enabled
- **State Paths**:
  - Dev: `envs/dev/terraform.tfstate`
  - Staging: `envs/stg/terraform.tfstate`
  - Production: `envs/prod/terraform.tfstate`

### Completed (Phase 2 - Partial) ✅
**Data Lake Module** (`modules/data_lake/`)
- ✅ S3 bucket deployed: `ai-dp-data-lake-dev-us-west-1`
- ✅ Three-layer architecture implemented:
  - `raw/` - Ingested data (30d→IA, 90d→Glacier, 180d expiration)
  - `processed/` - AI-enriched data (60d→IA, 120d→Glacier, 365d expiration)
  - `curated/` - Business-ready data (no lifecycle, permanent storage)
- ✅ Security features operational:
  - AES256 encryption at rest
  - Versioning enabled
  - Public access blocked (all 4 settings)
  - TLS/HTTPS enforced via bucket policy
- ✅ Provider default_tags pattern implemented (resolved tag conflicts)
- ✅ All three layers tested with sample data
- ✅ Lifecycle rules validated

**Key Achievements**:
- Resolved AWS tag conflict errors by centralizing tags in provider `default_tags`
- Implemented dynamic lifecycle rules to avoid empty rule errors
- Successfully tested batch uploads to all three data lake layers
- Established reusable tagging and lifecycle patterns for future modules

### Development Strategy
🔄 **Phase 1 (CI/CD) - Deferred**
- GitHub Actions CI/CD pipeline setup will be completed at the end
- AWS OIDC Identity Provider setup postponed
- Focus on core infrastructure implementation first

### In Progress
⏳ **Phase 2: Core Data Lake & Ingestion**
- Next: Build `modules/ingestion_stream/` (API Gateway, Kinesis)
- Next: Build `lambdas/etl/` (Kinesis consumer)

### Next Steps
1. ✅ ~~Data Lake Module~~ - COMPLETED
2. Build `modules/ingestion_stream/` module
   - API Gateway REST API for real-time ingestion
   - Kinesis Data Stream for buffering
   - EventBridge rule for S3 batch upload triggers
3. Build `lambdas/etl/` Lambda function
   - Kinesis stream consumer
   - Data validation and normalization
   - Write validated data to S3 `raw/` layer
4. Test end-to-end ingestion flow (batch and streaming)
5. Build `modules/step_functions/` for orchestration (Phase 3)
6. Build `modules/ai_enrichment/` for AI/ML services (Phase 3)
7. Return to Phase 1 (CI/CD) after core infrastructure is complete

### Progress Tracking
**Overall Completion**: ~15%

```
Phase 0 (Bootstrap):     ████████████████████ 100% ✅
Phase 1 (CI/CD):         ░░░░░░░░░░░░░░░░░░░░   0% ⏸️ (Deferred)
Phase 2 (Data Lake):     ████░░░░░░░░░░░░░░░░  20% ⏳ (data_lake done)
Phase 3 (Orchestration): ░░░░░░░░░░░░░░░░░░░░   0%
Phase 4 (Storage):       ░░░░░░░░░░░░░░░░░░░░   0%
Phase 5 (Analytics):     ░░░░░░░░░░░░░░░░░░░░   0%
Phase 6 (Security):      ░░░░░░░░░░░░░░░░░░░░   0%
Phase 7 (Production):    ░░░░░░░░░░░░░░░░░░░░   0%
```

## Lessons Learned & Best Practices

### Tag Configuration Pattern (CRITICAL)
**Problem**: Tag conflicts between provider `default_tags` and module-level tags cause AWS API errors (`InvalidTag: The TagValue you have provided is invalid`).

**Root Cause**: AWS Provider's `default_tags` (v3.38.0+) automatically applies tags to ALL resources. Manually adding the same tags in modules creates duplicates or conflicts.

**Solution Pattern**:
```hcl
# ✅ CORRECT: Provider level (envs/*/main.tf)
provider "aws" {
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

# ✅ CORRECT: Module level (modules/*/main.tf)
resource "aws_s3_bucket" "example" {
  bucket = "my-bucket"
  
  # Only resource-specific tags, NO duplicates with provider tags
  tags = {
    Name        = local.bucket_name
    Description = "Specific purpose"
  }
}

# ❌ WRONG: Don't merge provider tags in modules
locals {
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment  # ❌ Conflicts with provider default_tags!
      Project     = var.project_name # ❌ Conflicts with provider default_tags!
    }
  )
}
```

**Rule**: Provider `default_tags` handles global tags. Modules add only resource-specific tags.

---

### S3 Lifecycle Rules with Dynamic Blocks
**Problem**: Lifecycle rules with all values set to 0 (disabled) still create empty rules, which AWS rejects with error: `At least one action needs to be specified in a rule`.

**Solution**: Use dynamic blocks with conditional creation:
```hcl
# ✅ CORRECT: Rule only created when needed
dynamic "rule" {
  for_each = var.expiration_days > 0 || var.transition_to_ia_days > 0 || var.transition_to_glacier_days > 0 ? [1] : []
  
  content {
    id     = "lifecycle-rule"
    status = "Enabled"
    
    filter {
      prefix = "data/"
    }
    
    dynamic "expiration" {
      for_each = var.expiration_days > 0 ? [1] : []
      content {
        days = var.expiration_days
      }
    }
  }
}

# ❌ WRONG: Creates rule even when no actions configured
rule {
  id     = "lifecycle-rule"
  status = var.expiration_days > 0 ? "Enabled" : "Disabled"  # ❌ Still creates empty rule
  # ...
}
```

**Rule**: Wrap optional lifecycle rules in dynamic blocks with conditional `for_each`.

---

## Important Notes

- **Current Status**: Phase 0 completed (backend infrastructure configured). Skipping Phase 1 (CI/CD) to focus on core infrastructure first.
- **Roadmap**: See `docs/roadmap.md` for detailed implementation phases and completion criteria
- **Project Guide**: See `docs/ai-dp overview notion.md` for comprehensive architecture overview
- **Error Tracking**: Always consult and update `docs/errorlog.md` when debugging issues
