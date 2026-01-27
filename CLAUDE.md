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
├── envs/               # Environment-specific Terraform configs (dev, stg, prod)
├── modules/            # Reusable Terraform modules
│   ├── data_lake/      ├── ingestion_stream/   ├── step_functions/
│   ├── hot_store/      ├── orchestration/      └── analytics/
├── lambdas/            # Python Lambda functions (etl, merge, replay)
├── dashboard/          # Browser-based analytics dashboard
└── docs/               # Project documentation
```

## Current Status & Deployed Infrastructure

**Progress: 90% Complete (Phases 0-8 done, Phases 9-10 remaining)**

| Component | Resource Name | Status |
|-----------|---------------|--------|
| State Bucket | `tf-state-aidp` (us-west-1) | ✅ |
| Data Lake | `ai-dp-data-lake-dev-us-west-2` | ✅ |
| Kinesis | `ai-dp-dev-ingestion-stream` | ✅ |
| API Gateway | `https://<id>.execute-api.us-west-2.amazonaws.com/ingest` | ✅ |
| Step Functions | `ai-dp-dev-orchestrator` | ✅ |
| DynamoDB | `ai-dp-dev-enriched-data` | ✅ |
| Glue Database | `ai-dp-dev-analytics` | ✅ |
| Athena Workgroup | `ai-dp-dev-workgroup` | ✅ |

**Next:** Phase 9 (Production Hardening) → Phase 10 (CI/CD)

**For detailed phase history and achievements:** Read Serena memory `project-status-and-roadmap`

## Coding Standards & Principles

### Fundamental Development Principles
1. **NO HARDCODING**: All solutions must be generic and pattern-based
2. **ROOT CAUSE, NOT BANDAID**: Fix underlying structural issues, not symptoms
3. **DATA INTEGRITY**: Use consistent, authoritative data sources
4. **ASK QUESTIONS BEFORE CHANGING CODE**: Clarify requirements before implementing
5. **SECURITY-FIRST**: Use GitHub OIDC with short-lived tokens, never long-term credentials

### Portfolio Project Context
This is a **portfolio project for entry-level to intermediate cloud engineering roles**. See `.claude/agents/portfolio.md` for implementation guidelines.

**Key principles:**
- **WORKING > PERFECT** - Ship functional infrastructure first
- **EXPLAINABILITY FIRST** - If you can't explain it in an interview, simplify it
- **USE CONTEXT7** - Check for deprecations before implementing

### Serena MCP Tools (MANDATORY)
**ALWAYS use Serena's semantic code navigation tools when available:**
1. Use `get_symbols_overview` BEFORE reading entire files
2. Use `find_symbol` with `name_path_pattern` for precise targeting
3. Use `find_referencing_symbols` to trace dependencies
4. Use `replace_symbol_body` for precise symbol-level edits

**Rule**: Only fall back to Read/Edit/Grep when Serena isn't applicable (non-code files, line-specific edits).

### Code Quality
- Prefer simple solutions over complex ones
- Keep files under 200-300 lines
- Only make changes that are requested or directly related
- Avoid over-engineering and unnecessary abstractions

### Terraform Style
- Use decorative comment headers: `#-------------------- Resource Name --------------------#`
- Separate IAM into dedicated `iam.tf` files
- Standard module structure: `main.tf`, `iam.tf`, `variables.tf`, `outputs.tf`, `README.md`

### Error Handling (CRITICAL)
**MANDATORY PROCESS:**
1. **BEFORE fixing errors**: Read `docs/errorlog.md` for existing solutions
2. **WHEN errors occur**: Document in `docs/errorlog.md` immediately
3. **If error exists in log**: Apply the documented solution

## Infrastructure Design Patterns

### Terraform Backend
```hcl
backend "s3" {
  bucket       = "tf-state-aidp"
  key          = "envs/dev/terraform.tfstate"
  region       = "us-west-1"
  encrypt      = true
  use_lockfile = true  # Native S3 locking, no DynamoDB needed
}
```

### Tag Configuration (CRITICAL)
- Provider `default_tags` handles global tags (Environment, Project, ManagedBy)
- Modules add only resource-specific tags (Name, Description)
- **Never duplicate provider tags in modules** (causes AWS API errors)

### S3 Lifecycle Rules
- Use dynamic blocks with conditional `for_each` to avoid empty rule errors
- See `docs/errorlog.md` for details

## Development Commands

```powershell
# Terraform workflow
terraform -chdir=envs/dev fmt && terraform -chdir=envs/dev validate
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev apply

# Test streaming ingestion
curl -X POST "https://<api-id>.execute-api.us-west-2.amazonaws.com/ingest" `
  -H "Content-Type: application/json" -H "X-Partition-Key: test" `
  -d '{"event_type":"test","event_timestamp":"2026-01-25T12:00:00Z"}'

# Test batch ingestion
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json
```

## Quick Reference

| Need | Where to Look |
|------|---------------|
| Detailed phase history | Serena memory: `project-status-and-roadmap` |
| Full roadmap | `docs/roadmap.md` |
| Error solutions | `docs/errorlog.md` |
| Architecture overview | `docs/ai-dp overview notion.md` |
| Terraform patterns | Serena memory: `coding-standards` |
| Implementation guide | `.claude/agents/portfolio.md` |

## Important Notes

- **Application Region**: `us-west-2` (all resources except state bucket)
- **Backend Region**: `us-west-1` (state bucket only)
- **CI/CD**: Deferred to Phase 10 (after infrastructure proven working)
- **Learning Project**: Keep complexity appropriate, prioritize understanding
