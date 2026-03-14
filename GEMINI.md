# GEMINI.md

This file provides guidance to Google's Gemini assistant when working with code in this repository.

## Project Overview

This is an **AI-Powered Serverless Data Pipeline** built on AWS infrastructure managed with Terraform. The pipeline ingests both batch and streaming data, enriches it with AWS AI services (Comprehend, SageMaker), and provides analytics through a dual storage strategy (DynamoDB for hot data, S3 Data Lake for historical queries).

**Key Technologies:**
- Infrastructure: Terraform >= 1.11.0 with S3 backend (native locking via `use_lockfile = true`)
- Compute: AWS Lambda, Step Functions, EventBridge
- Data Ingestion: API Gateway → Kinesis Data Streams (on-demand billing), S3 batch uploads
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

### Portfolio Implementation Agent
**This project is a portfolio project for entry-level to intermediate cloud engineering roles.**

When implementing Terraform modules or AWS infrastructure, follow the **Portfolio Implementation Agent** guidelines in `.claude/agents/portfolio.md`. This agent provides:

- **Portfolio-appropriate complexity**: Simple enough to explain in interviews, complex enough to demonstrate skills
- **Research-driven development**: Research AWS services BEFORE implementing to avoid deprecated resources
- **Entry-level focus**: Working > Perfect, Explainability First
- **Interview preparation**: Code should help answer common technical questions
- **Modern best practices**: Use current AWS patterns without enterprise over-engineering

**Key principles from portfolio agent:**
1. **WORKING > PERFECT** - Ship functional infrastructure first
2. **USE TOOLS TO STAY CURRENT** - Check for deprecations before implementing
3. **NO SECRETS IN CODE** - Never hardcode credentials
4. **EXPLAINABILITY FIRST** - If you can't explain it in an interview, simplify it
5. **DOCUMENT YOUR DECISIONS** - Comments explain "why," not just "what"

**When to use**: For all Terraform module implementations (ingestion_stream, step_functions, ai_enrichment, etc.)

### Gemini Tool Usage (MANDATORY)
**ALWAYS use your available tools efficiently when working on this project.**

1.  **Understand the codebase:**
    *   Use `glob` to find files. For example, `glob(pattern='**/*.tf')` to find all Terraform files.
    *   Use `search_file_content` for targeted code search instead of reading entire files.
    *   Use `read_file` to examine specific files.
    *   For complex queries about the codebase, use `delegate_to_agent(agent_name='codebase_investigator', objective='...')`.

2.  **Making changes:**
    *   Use `write_file` to create new files.
    *   Use `replace` for targeted, precise changes in existing files. Always read the file first to get the exact `old_string` content.
    *   Use `run_shell_command` to execute commands like `terraform`, `pip`, `pytest`, etc.

3.  **Research & Investigation:**
    *   Use `google_web_search` to research AWS best practices, Terraform provider documentation, or any error messages.
    *   Use `delegate_to_agent(agent_name='codebase_investigator', ...)` for broad, exploratory tasks or to get a high-level overview.

**Why use these tools?**
- **Efficiency**: They are optimized for performance and reduce unnecessary output.
- **Precision**: They allow for targeted actions, which is safer than manual editing.
- **Power**: They provide advanced capabilities like codebase analysis and web search.

**Rule**: Before taking any action, consider which tool is the best fit for the job.

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

**Module File Organization:**
- Separate IAM resources into dedicated `iam.tf` files within each module
- Keep `main.tf` focused on core infrastructure resources (S3, Lambda, API Gateway, etc.)
- Standard module structure:
  - `main.tf` - Core infrastructure resources
  - `iam.tf` - All IAM roles, policies, and attachments
  - `variables.tf` - Input variables
  - `outputs.tf` - Output values
  - `README.md` - Module documentation
- Benefits: Easier security reviews, better organization, cleaner main.tf files

### Environment & Security
- Write code that accounts for different environments: dev, stg, prod
- Never overwrite `.env` files without asking first
- Mock data only for tests, never for dev or prod
- **Environment Isolation**: Maintain strict separation between dev/staging/prod (ideally separate AWS accounts)
- **Zero-Trust**: All AWS access via short-lived tokens and least-privilege IAM roles

### Error Handling (CRITICAL)
**MANDATORY PROCESS - No exceptions:**
1. **BEFORE attempting any error fix** (whether you encounter it or the user reports it):
   Read `docs/errorlog.md` to check for similar issues and existing solutions
2. **WHEN ANY error occurs in the project**: Immediately document in `docs/errorlog.md`:
   - Error message (exact text)
   - Attempted solutions (what didn't work)
   - Working fix (what solved it)
3. **NEVER skip documentation**: Every error is a learning opportunity
4. **If error exists in log**: Reference the error number and apply the documented solution

**Rule**: If an error occurs and errorlog.md isn't checked/updated, you're doing it wrong.

## Infrastructure Design Patterns

### Terraform Backend Configuration
This project uses **Terraform >= 1.11.0** with S3 native state locking (`use_lockfile = true`), eliminating the need for DynamoDB lock tables.

Example `backend.tf`:
```hcl
terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "tf-state-aidp"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-west-1"  # Backend bucket in us-west-1 (separate from application resources)
    encrypt      = true
    use_lockfile = true  # Native S3 locking, no DynamoDB needed
  }
}

# Application resources deployed in us-west-2 (see envs/dev/variables.tf)
```

### Module Wiring Pattern
Root `main.tf` files in `envs/{dev,stg,prod}/` wire together modules from `modules/`. Modules pass outputs between each other (e.g., `data_lake.raw_bucket_arn` → `ingestion_stream` module).

### Feature Flags
Use Terraform variables for feature toggles:
- `feature_rekognition_on`: Enable/disable image labeling
- `create_quicksight`: Enable/disable QuickSight dashboard creation

## GitHub Actions CI/CD (Phase 10 - Final)

> **Note:** CI/CD implementation deferred to Phase 10 after all infrastructure is built and proven working.

**When implemented (Phase 10):**

**CI Workflow** (on PRs):
- Terraform fmt/validate/plan
- tflint, tfsec security scanning
- PR comment with plan output

**Deploy Workflow** (on main branch):
- OIDC authentication (no long-term credentials)
- Environment promotion: dev → stg → prod
- Manual approval gates between environments
- Auto-deploy to dev, manual approve for staging/prod

**Why last?** Deployment automation is most valuable once infrastructure is stable and tested.

## Common Tasks

### Adding a New Terraform Module
**Follow the Portfolio Implementation Agent workflow** (`.claude/agents/portfolio.md`):
1. **Research with `google_web_search`**: Check AWS service and Terraform provider documentation for current best practices and deprecations.
2. **Create module structure**: `modules/<module_name>/` with these files:
   - `main.tf` - Core infrastructure resources only (S3, Lambda, API Gateway, etc.)
   - `iam.tf` - All IAM roles, policies, and policy attachments
   - `variables.tf` - Input variables
   - `outputs.tf` - Output values
   - `README.md` - Module documentation
3. **Implement with portfolio principles**: Working > Perfect, keep it explainable, use clear comments
4. **Wire module**: Add to environment-specific `main.tf` files
5. **Test**: Validate with `run_shell_command('terraform fmt')` and `run_shell_command('terraform validate')`, then deploy to dev.
6. **Document**: Update README with usage examples and talking points for interviews.

**IAM File Organization Rule**: Always create a separate `iam.tf` file for IAM resources. This keeps security-related resources isolated for easier review and maintains clean, focused `main.tf` files.

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

> **Note:** Roadmap reorganized on 2025-01-24 for strict sequential implementation. CI/CD moved from Phase 1 to Phase 10 (final phase).
> **Latest Update:** 2026-01-24 - Dashboard optimization: Moved sentiment chart and total count from Athena to Curated S3 for instant loading (~100ms vs ~3s).

### Completed ✅

**Phase 0: Bootstrap Infrastructure**
- S3 state bucket created: `tf-state-aidp`
- Backend configurations created for all environments (dev, stg, prod)
- All three environments initialized with S3 backend
- Backend uses Terraform 1.13.0 with native S3 locking (`use_lockfile = true`)

**Phase 1: Data Lake Foundation (All Tasks Complete)**
- ✅ S3 bucket deployed: `ai-dp-data-lake-dev-us-west-2`
- ✅ Three-layer architecture implemented: `raw/`, `processed/`, `curated/`
- ✅ Security features operational
- ✅ EventBridge notifications enabled

**Phase 2: Streaming Ingestion Path (All Tasks Complete)**
- ✅ HTTP API Gateway, Kinesis Data Stream, ETL Lambda, and DLQ all operational.
- ✅ End-to-end streaming path tested.

**Phase 3: Batch Ingestion Path (All Tasks Complete)**
- ✅ EventBridge rule deployed and tested.

**Phase 4: Step Functions & EventBridge Wiring (All Tasks Complete)**
- ✅ Step Functions state machine deployed and integrated with EventBridge.

**Phase 5: DynamoDB Hot Store (All Tasks Complete)**
- ✅ DynamoDB table with GSI and TTL deployed and tested.

**Phase 6: AI Enrichment Services (All Tasks Complete)**
- ✅ Step Functions state machine updated with parallel Comprehend tasks.

**Phase 7: Merge Lambda & Complete Orchestration (All Tasks Complete)**
- ✅ Merge Lambda created, and both streaming and batch pipelines are fully operational.

**Phase 8: Analytics & Query Layer (All Tasks Complete)**
- ✅ Glue Catalog, Crawler, Athena workgroup, and a browser-based dashboard are all deployed and functional.

### Next Steps

**Phase 9: Production Hardening**
1. Add CloudWatch alarms for all critical components
2. Implement comprehensive error handling and monitoring
3. Add API Gateway throttling and rate limiting
4. Configure auto-scaling for production workloads

**Phases 9-10:** See `docs/roadmap.md` for detailed sequential plan

### Progress Tracking

**Overall Completion**: ~90% (9 of 10 phases complete)

```
Phase 0 (Bootstrap):           ████████████████████ 100% ✅
Phase 1 (Data Lake):           ████████████████████ 100% ✅
Phase 2 (Streaming):           ████████████████████ 100% ✅
Phase 3 (Batch EventBridge):  ████████████████████ 100% ✅
Phase 4 (Step Functions):     ████████████████████ 100% ✅
Phase 5 (DynamoDB):            ████████████████████ 100% ✅
Phase 6 (AI Enrichment):       ████████████████████ 100% ✅
Phase 7 (Merge & Orchestrate): ████████████████████ 100% ✅
Phase 8 (Analytics):           ████████████████████ 100% ✅
Phase 9 (Production Hardening):░░░░░░░░░░░░░░░░░░░░   0%
Phase 10 (CI/CD):              ░░░░░░░░░░░░░░░░░░░░   0%
```

**See `docs/roadmap.md` for complete phase-by-phase implementation plan.**

## Lessons Learned & Best Practices

### Tag Configuration Pattern (CRITICAL)
**Problem**: Tag conflicts between provider `default_tags` and module-level tags cause AWS API errors (`InvalidTag: The TagValue you have provided is invalid`).

**Solution Pattern**: Define global tags in the provider `default_tags` block. In modules, only add resource-specific tags. Do not merge global tags inside modules.

### S3 Lifecycle Rules with Dynamic Blocks
**Problem**: Lifecycle rules with all values set to 0 (disabled) still create empty rules, which AWS rejects.

**Solution**: Use dynamic blocks with a conditional `for_each` to create the rule only when it's needed.

## Important Notes

- **Portfolio Project**: This is a portfolio project for entry-level to intermediate cloud engineering roles. Focus on working, explainable infrastructure.
- **Roadmap**: The project follows a strict, sequential 10-phase implementation plan.
- **Error Tracking**: Always consult and update `docs/errorlog.md` when debugging issues.
