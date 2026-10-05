# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **AI-Powered Serverless Data Pipeline** built on AWS infrastructure managed with Terraform. The pipeline ingests both batch and streaming data, enriches it with Amazon Comprehend (sentiment and entity detection), and provides analytics through a dual storage strategy (DynamoDB for hot data, S3 Data Lake for historical queries).

**Key Technologies:**
- Infrastructure: Terraform >= 1.11.0 with S3 backend (native locking via `use_lockfile = true`)
- Compute: AWS Lambda, Step Functions, EventBridge
- Data Ingestion: API Gateway → Kinesis Data Streams, S3 batch uploads
- AI/ML: Amazon Comprehend (DetectSentiment, DetectEntities)
- Storage: S3 (raw/processed/curated layers), DynamoDB, Glue + Athena
- Observability: CloudWatch, X-Ray, SQS DLQs

> **For full architecture context:** Load Serena memory `project-overview` before making technology or integration decisions.

## Repository Structure

```
AI-DP/
├── envs/               # Environment-specific Terraform configs (dev active)
├── modules/            # Reusable Terraform modules
│   ├── data_lake/      ├── ingestion_stream/   ├── step_functions/
│   ├── hot_store/      ├── orchestration/      ├── analytics/
│   └── observability/  # CloudWatch dashboard + alarms + SNS
├── lambdas/            # Python Lambda functions (etl, merge)
├── dashboard/          # Browser-based analytics dashboard
├── scripts/            # load_test.py, rebuild_summary.py
├── test-data/batch/    # 8 sample .txt files for batch-path testing
└── docs/               # Project documentation
```

> **For full module details and file locations:** Load Serena memory `repository-structure` before navigating or modifying modules.

## Current Status & Deployed Infrastructure

**Progress: 100% Complete ✅ — All phases done (2026-04-05)**

| Component | Resource Name | Status |
|-----------|---------------|--------|
| State Bucket | `tf-state-aidp` (us-west-1) | ✅ |
| Data Lake | `ai-dp-data-lake-dev-us-west-2` | ✅ |
| Kinesis | `ai-dp-dev-ingestion-stream` (KMS, PROVISIONED 1-shard) | ✅ |
| API Gateway | `ai-dp-dev-ingestion-api` (URL: `terraform -chdir=envs/dev output api_gateway_invoke_url`) | ✅ |
| Step Functions | `ai-dp-dev-orchestrator` | ✅ |
| DynamoDB | `ai-dp-dev-enriched-data` | ✅ |
| Glue Database | `ai-dp-dev-analytics` | ✅ |
| Athena Workgroup | `ai-dp-dev-workgroup` | ✅ |
| CloudWatch Dashboard | `ai-dp-dev-operations` | ✅ |
| CloudWatch Alarms | 5 alarms + SNS topic | ✅ |
| AWS Budget | `ai-dp-dev-monthly-budget` ($50/month) | ✅ |
| GitHub Actions OIDC Role | `ai-dp-dev-github-actions` | ✅ |

**Phase 9 Progress (7/7 tasks) ✅ COMPLETE:**
- ✅ Lambda unit tests (42 tests, 95% coverage; CI gate at 90%)
- ✅ Load testing (1000 events, 0% errors)
- ✅ CloudWatch Dashboard (8 widgets)
- ✅ CloudWatch Alarms + SNS notifications
- ✅ Security Review (IAM audit, encryption verification, tfsec scan)
- ✅ Cost Optimization Review (Budget alerts, lifecycle audit, $12/month actual)
- ✅ Architecture Documentation — `docs/architecture.md` (Mermaid diagrams, sequence flows, API contract)

**Phase 10 Progress (6/6 tasks) ✅ COMPLETE:**
- ✅ **OIDC IAM Role Setup** — `ai-dp-dev-github-actions` role with least-privilege policy, imported into Terraform state
- ✅ **CI Workflow** — `.github/workflows/ci.yml` runs fmt/validate/tflint/tfsec/plan on every PR, posts plan as PR comment
- ✅ **Deploy Workflow** — `.github/workflows/deploy.yml` runs `terraform apply` on merge to main
- ✅ **Environment Protection** — `dev` GitHub Environment created
- ✅ **Workflow Testing** — both workflows verified end-to-end
- ✅ **CI/CD Documentation** — `docs/cicd.md`

**Project is complete. No remaining tasks.**

**Post-completion maintenance (2026-06-28):** Kinesis capacity mode is parameterized (`kinesis_stream_mode`, default `PROVISIONED` 1-shard ≈ $11/mo). It had drifted to `ON_DEMAND` (flat ≈ $29/mo regardless of throughput) during Phase 9 load testing and was left there; reverted to provisioned, and `test/deploy-workflow` was merged to `main` via PR #2. Toggle `ON_DEMAND` only for burst load tests, then revert.

**Post-completion maintenance (2026-08-31):** Batch-path testing surfaced and fixed two latent bugs — see `docs/errorlog.md` Error #6.

- **Lost-update race in the curated summary (FIXED, deployed).** Eight concurrent batch uploads produced 9 records but a summary reading 7. `update_curated_summary` did an unguarded read-modify-write on one shared S3 object. Now uses conditional writes (`IfMatch` on the ETag; `IfNoneMatch='*'` on create) with bounded retries and jittered exponential backoff. Verified by re-running the failing scenario: 17 records, summary reads 17, with real `PreconditionFailed` retries in CloudWatch proving the mechanism engages. **Known limit:** makes lost updates rare, not impossible; a DynamoDB atomic counter (`ADD`) is the right fix at higher write rates.
- **`get_text_preview` assumed JSON (FIXED, deployed).** Held for seven months because only the streaming path (which writes JSON) was exercised. Plain-text batch files made `json.loads` raise into a broad `except`, silently emptying previews. Now falls back to the raw body on `json.JSONDecodeError`, so both ingestion paths produce identical record shapes.
- **Text preview feature completed.** The `td.text-preview` CSS had existed unused since a removed column; added the `Text` column to the dashboard table with full text in a `title` tooltip on hover, and corrected all `colspan` values from 4 to 5.
- **New tooling:** `scripts/rebuild_summary.py` (recomputes the summary from DynamoDB; absolute write, idempotent, `--dry-run`) and the `/reset-data` slash command (clears only the two sources the dashboard reads, never `raw/` or `processed/`).

**Comprehend input contract:** Step Functions routes on the object key. Keys ending in `.json` (the streaming path) are parsed with `States.StringToJson` and only the `text` field is scored; events without `text` end at `NoTextToAnalyze` with no Comprehend calls. Any other key is treated as plain text and the **entire body** is scored. Keep each document under **5,000 bytes** (`DetectSentiment`'s limit; `DetectEntities` allows 100 KB, so sentiment binds). EventBridge matches any key under `raw/`. One file = one record = one sentiment.

**For full phase history, achievements, and next steps:** Load Serena memory `project-status-and-roadmap`.

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
Serena memories live in `.serena/memories/`, which is gitignored (local only).

**ALWAYS use Serena's semantic code navigation tools when available:**
1. Use `get_symbols_overview` BEFORE reading entire files
2. Use `find_symbol` with `name_path_pattern` for precise targeting
3. Use `find_referencing_symbols` to trace dependencies
4. Use `replace_symbol_body` for precise symbol-level edits

**Rule**: Only fall back to Read/Edit/Grep when Serena isn't applicable (non-code files, line-specific edits).

> **For full coding rules, patterns, and anti-patterns:** Load Serena memory `coding-standards` before writing any code or Terraform.

### Code Quality
- Prefer simple solutions over complex ones
- Keep files under 200-300 lines
- Only make changes that are requested or directly related
- Avoid over-engineering and unnecessary abstractions

### Terraform Style
- Separate IAM into dedicated `iam.tf` files
- Standard module structure: `main.tf`, `iam.tf`, `variables.tf`, `outputs.tf`, `README.md`
- Comments explain **why** decisions were made, not **what** the code does

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

> **For full Terraform patterns and examples:** Load Serena memory `coding-standards` before implementing infrastructure.

## Development Commands

```powershell
# Terraform workflow
terraform fmt -recursive && terraform -chdir=envs/dev validate   # fmt from repo root, same as CI
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev apply

# Load test (sends 1,000 events to Kinesis via boto3)
python scripts/load_test.py

# Repair curated summary drift from DynamoDB (always --dry-run first)
python scripts/rebuild_summary.py --dry-run
python scripts/rebuild_summary.py

# Batch-path test: 8 sample .txt files -> 8 concurrent Step Functions executions
aws s3 cp test-data/batch/ s3://ai-dp-data-lake-dev-us-west-2/raw/batch-test/ `
  --recursive --exclude README.md --region us-west-2

# Test streaming ingestion
curl -X POST "https://<api-id>.execute-api.us-west-2.amazonaws.com/ingest" `
  -H "Content-Type: application/json" -H "X-Partition-Key: test" `
  -d '{"event_type":"test","event_timestamp":"2026-01-25T12:00:00Z","text":"Fast shipping, great product."}'

# Test batch ingestion
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json
```

> **For full command reference and workflow:** Load Serena memories `suggested_commands` and `terraform-workflow-commands` before running unfamiliar commands.

## Quick Reference

| Need | Where to Look |
|------|---------------|
| Detailed phase history | Serena memory: `project-status-and-roadmap` |
| Full roadmap | `docs/roadmap.md` |
| Error solutions | `docs/errorlog.md` |
| Architecture overview | `docs/ai-dp overview notion.md` |
| How the dashboard works | `docs/dashboard-explained.md` |
| Reset data for a clean retest | `/reset-data` slash command |
| Deploy, rollback, alarm response, DLQ replay | `docs/runbooks.md` |
| Terraform patterns | Serena memory: `coding-standards` |
| Implementation guide | `.claude/agents/portfolio.md` |

## Important Notes

- **Application Region**: `us-west-2` (all resources except state bucket)
- **Backend Region**: `us-west-1` (state bucket only)
- **CI/CD**: GitHub Actions with OIDC (see `docs/cicd.md`)
- **Learning Project**: Keep complexity appropriate, prioritize understanding
