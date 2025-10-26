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

### Portfolio Implementation Agent
**This project is a portfolio project for entry-level to intermediate cloud engineering roles.**

When implementing Terraform modules or AWS infrastructure, follow the **Portfolio Implementation Agent** guidelines in `.claude/agents/portfolio.md`. This agent provides:

- **Portfolio-appropriate complexity**: Simple enough to explain in interviews, complex enough to demonstrate skills
- **Context7 integration**: Research AWS services BEFORE implementing to avoid deprecated resources
- **Entry-level focus**: Working > Perfect, Explainability First
- **Interview preparation**: Code should help answer common technical questions
- **Modern best practices**: Use current AWS patterns without enterprise over-engineering

**Key principles from portfolio agent:**
1. **WORKING > PERFECT** - Ship functional infrastructure first
2. **USE CONTEXT7 TO STAY CURRENT** - Check for deprecations before implementing
3. **NO SECRETS IN CODE** - Never hardcode credentials
4. **EXPLAINABILITY FIRST** - If you can't explain it in an interview, simplify it
5. **DOCUMENT YOUR DECISIONS** - Comments explain "why," not just "what"

**When to use**: For all Terraform module implementations (ingestion_stream, step_functions, ai_enrichment, etc.)

### Instruction Hierarchy

When using specialized agents (like `.claude/agents/portfolio.md`), follow this hierarchy for resolving conflicts:

1. **CLAUDE.md = Universal Project Rules** (Foundation)
   - Foundation-level principles that always apply to the entire project
   - Examples: "No secrets in code," "Check errorlog.md before fixing errors," "This is a portfolio project"
   - **Sets the boundaries and project context**

2. **Specialized Agents = Implementation Guides** (Task-Specific)
   - Provides HOW to achieve CLAUDE.md goals for specific tasks (Terraform, Python, etc.)
   - More specific guidance within CLAUDE.md boundaries
   - Examples: "Use Context7 before implementing," "Keep modules under 300 lines"
   - **Tells HOW to achieve CLAUDE.md goals**

3. **Conflict Resolution Rules**:
   - **Agent CONTRADICTS CLAUDE.md fundamentals**: ✅ CLAUDE.md wins (universal security/principle rules)
   - **Agent SPECIFIES HOW to achieve CLAUDE.md goals**: ✅ Agent wins (more specific guidance)
   - **Both say the same thing differently**: ✅ Use agent wording (task-specific context)

**Example**: CLAUDE.md says "no secrets in code" (fundamental security rule). Portfolio.md says "use Context7 before implementing" (specific workflow). Both apply - no conflict. Portfolio.md adds specificity without contradicting fundamentals.

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
1. **Research with Context7**: Check AWS service and Terraform resource documentation for current best practices and deprecations
2. **Create module structure**: `modules/<module_name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
3. **Implement with portfolio principles**: Working > Perfect, keep it explainable, use clear comments
4. **Wire module**: Add to environment-specific `main.tf` files
5. **Test**: Validate with `terraform fmt` and `terraform validate`, then deploy to dev
6. **Document**: Update README with usage examples and talking points for interviews

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

### Completed ✅

**Phase 0: Bootstrap Infrastructure**
- S3 state bucket created: `tf-state-aidp`
- Backend configurations created for all environments (dev, stg, prod)
- All three environments initialized with S3 backend
- Backend uses Terraform 1.13.0 with native S3 locking (`use_lockfile = true`)

**Backend Configuration Details:**
- **Bucket**: `tf-state-aidp`
- **Region**: `us-west-1`
- **Encryption**: Enabled
- **State Paths**:
  - Dev: `envs/dev/terraform.tfstate`
  - Staging: `envs/stg/terraform.tfstate`
  - Production: `envs/prod/terraform.tfstate`

**Phase 1: Data Lake Foundation (Task 1)**
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

**Key Achievements:**
- Resolved AWS tag conflict errors by centralizing tags in provider `default_tags`
- Implemented dynamic lifecycle rules to avoid empty rule errors
- Successfully tested batch uploads to all three data lake layers
- Established reusable tagging and lifecycle patterns for future modules

### In Progress ⏳

**Phase 1: Data Lake Foundation (Task 2)**
- Pending: Enable S3 EventBridge notifications on data lake bucket
- This is required before Phase 3 (Batch EventBridge setup)

### Next Steps

**Immediate (Complete Phase 1):**
1. Add `aws_s3_bucket_notification` resource to `modules/data_lake/main.tf` with `eventbridge = true`

**Phase 2: Streaming Ingestion Path**
2. Build `modules/ingestion_stream/` module (Part 1):
   - HTTP API Gateway with POST endpoint
   - Kinesis Data Stream (1 shard for dev)
   - API Gateway → Kinesis integration
3. Build `lambdas/etl/` Lambda function with DLQ
4. Wire Lambda to `ingestion_stream` module (Part 2)
5. Test end-to-end streaming: API → Kinesis → Lambda → S3 `raw/`

**Phase 3: Batch Ingestion Path**
6. Add EventBridge rule to `ingestion_stream` module (Part 3)
7. Test S3 upload detection (no target yet)

**Phase 4: Step Functions & EventBridge Wiring**
8. Build `modules/step_functions/` (minimal Pass state)
9. Wire EventBridge target to Step Functions

**Phases 5-10:** See `docs/roadmap.md` for detailed sequential plan

### Development Strategy

✅ **Sequential Implementation Approach**
- Build strictly in phase order (0 → 1 → 2 → 3 → ... → 10)
- No "placeholders for later" - only build what's needed NOW
- Resources created when needed (DynamoDB in Phase 5, before Phase 7 uses it)
- **CI/CD deferred to Phase 10** (after infrastructure proven working)

### Progress Tracking

**Overall Completion**: ~20% (2 of 10 phases complete)

```
Phase 0 (Bootstrap):           ████████████████████ 100% ✅
Phase 1 (Data Lake):           ████████████████████ 100% ✅ (Task 1) | ⏳ (Task 2 pending)
Phase 2 (Streaming):           ░░░░░░░░░░░░░░░░░░░░   0%
Phase 3 (Batch EventBridge):  ░░░░░░░░░░░░░░░░░░░░   0%
Phase 4 (Step Functions):     ░░░░░░░░░░░░░░░░░░░░   0%
Phase 5 (DynamoDB):            ░░░░░░░░░░░░░░░░░░░░   0%
Phase 6 (AI Enrichment):       ░░░░░░░░░░░░░░░░░░░░   0%
Phase 7 (Merge & Orchestrate): ░░░░░░░░░░░░░░░░░░░░   0%
Phase 8 (Analytics):           ░░░░░░░░░░░░░░░░░░░░   0%
Phase 9 (Production Hardening):░░░░░░░░░░░░░░░░░░░░   0%
Phase 10 (CI/CD):              ░░░░░░░░░░░░░░░░░░░░   0%
```

**See `docs/roadmap.md` for complete phase-by-phase implementation plan.**

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

- **Portfolio Project**: This is a portfolio project for entry-level to intermediate cloud engineering roles. Focus on working, explainable infrastructure over enterprise perfection. See `.claude/agents/portfolio.md` for implementation guidelines.
- **Learning Project**: The developer is learning as we go. Keep complexity appropriate (intermediate level), prioritize understanding, and ensure every implementation can be explained in an interview.
- **Roadmap Reorganization (2025-01-24)**: Roadmap restructured for strict sequential implementation. CI/CD moved from Phase 1 to Phase 10 (final phase). Now building in order: Bootstrap → Data Lake → Streaming → Batch → Step Functions → DynamoDB → AI → Merge → Analytics → Hardening → CI/CD.
- **Current Status**: Phase 1 Task 2 in progress (Enable S3 EventBridge notifications). See `docs/status.md` for quick status overview.
- **Roadmap**: See `docs/roadmap.md` for detailed 10-phase sequential implementation plan
- **Project Guide**: See `docs/ai-dp overview notion.md` for comprehensive architecture overview
- **Error Tracking**: Always consult and update `docs/errorlog.md` when debugging issues
- **Implementation Agent**: Use the Portfolio Implementation Agent (`.claude/agents/portfolio.md`) for all Terraform module work
