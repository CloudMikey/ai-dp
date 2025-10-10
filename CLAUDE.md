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

## Important Notes

- **Current Status**: This project is in early development (Phase 0-1 of roadmap). Most modules and Lambda functions are not yet implemented.
- **Roadmap**: See `docs/roadmap.md` for detailed implementation phases and completion criteria
- **Project Guide**: See `docs/ai-dp overview notion.md` for comprehensive architecture overview
- **Error Tracking**: Always consult and update `docs/errorlog.md` when debugging issues
