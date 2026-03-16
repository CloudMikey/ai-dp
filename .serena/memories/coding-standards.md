# Coding Standards & Development Principles

## Fundamental Rules (Display When Making Code Changes)
1. **NO HARDCODING**: All solutions must be generic and pattern-based
2. **ROOT CAUSE, NOT BANDAID**: Fix underlying structural issues, not symptoms
3. **DATA INTEGRITY**: Use consistent, authoritative data sources
4. **ASK QUESTIONS BEFORE CHANGING CODE**: Clarify requirements first
5. **SECURITY-FIRST**: GitHub OIDC with short-lived tokens, never long-term credentials

## Code Quality
- Prefer simple over complex; avoid over-engineering
- Files max 200-300 lines — refactor if larger
- Only make requested changes (no unsolicited improvements)
- No speculative/future-proofing features
- No mock data in dev/prod (only in tests)
- Never overwrite `.env` files without confirmation

## Terraform Style
### Section Headers
```hcl
#-------------------- DynamoDB Table --------------------#
#-------------------- Lambda Resources --------------------#
```

### Resource Comments
```hcl
# This DynamoDB table stores enriched event data with 30-day TTL.
resource "aws_dynamodb_table" "enriched_data" { ... }
```

### Rules
- IAM resources go in dedicated `iam.tf` files (separate from `main.tf`)
- All variables must have `description` (TFLint enforced)
- All outputs must have `description` (TFLint enforced)
- Variable types must be explicit (TFLint enforced)
- Naming convention: `snake_case` (TFLint enforced)
- Tags: provider `default_tags` handles global tags; modules add only resource-specific tags
  - **NEVER duplicate provider tags in modules** (causes AWS API errors)
- Required tags: `Environment`, `Project`, `ManagedBy` (in provider default_tags)

### Terraform Backend Pattern
```hcl
backend "s3" {
  bucket       = "tf-state-aidp"
  key          = "envs/dev/terraform.tfstate"
  region       = "us-west-1"
  encrypt      = true
  use_lockfile = true  # Native S3 locking, NO DynamoDB table needed
}
```

### S3 Lifecycle Rules
Use dynamic blocks with conditional `for_each` to avoid empty rule errors. See `docs/errorlog.md`.

## Python Lambda Standards
- Use `logging` module (not `print`)
- Environment variables for config (no hardcoded values)
- `try/except` error handling
- Idempotency (safe to reprocess same event)
- SQS DLQ for async error handling

## Anti-Patterns to Avoid
- ❌ Hardcoded account IDs, regions, ARNs
- ❌ Wildcard IAM permissions without justification
- ❌ Missing DLQs for async Lambda invocations
- ❌ Long-term AWS credentials anywhere
- ❌ Files > 300 lines without refactoring
- ❌ Creating new patterns when existing ones suffice
- ❌ Duplicate provider default_tags in module resources

## Error Handling Protocol
1. **BEFORE fixing**: Read `docs/errorlog.md` for existing solutions
2. **WHEN errors occur**: Document in `docs/errorlog.md` immediately
3. **If error exists in log**: Apply the documented solution
