# Coding Standards & Development Principles

## Fundamental Development Principles
**ALWAYS display these at the start of responses when making code changes:**

1. **NO HARDCODING, EVER**: All solutions must be generic, pattern-based, and work across all commands, not just specific examples
2. **ROOT CAUSE, NOT BANDAID**: Fix the underlying structural or data lineage issues, not symptoms
3. **DATA INTEGRITY**: Use consistent, authoritative data sources (Stage 1 raw JSON for table locations, parsed Stage 3 for final command structure)
4. **ASK QUESTIONS BEFORE CHANGING CODE**: If you have questions, ask them before you start changing code
5. **SECURITY-FIRST APPROACH**: Prioritize GitHub OIDC authentication over long-term credentials, use short-lived tokens and least-privilege IAM roles

## Code Quality & Simplicity

- **Always prefer simple solutions** over complex ones
- **Avoid duplication**: Check for existing similar functionality in the codebase before implementing new code
- **Keep codebase clean and organized**
- **File size limits**: Avoid files over 200-300 lines of code—refactor at that point
- **Only make requested changes**: Don't add changes beyond what's requested or directly related

## Development Practices

### Change Management
- Only make changes that are requested or directly related to the requested change
- When fixing bugs, exhaust existing implementation options before introducing new patterns or technologies
- If new patterns are introduced, remove old implementations to prevent duplicate logic
- Avoid building speculative functionality—implement features only when needed

### Environment & Data Management
- **Write code for multiple environments**: dev, test, and prod
- **Mock data only for tests**, never for dev or prod environments
- **Never add stubbing or fake data** patterns affecting dev or prod
- **Never overwrite `.env` files** without asking and confirming first
- **Always use up-to-date Terraform resources**

### Security Requirements
- **Zero-Trust Principle**: All AWS access must use short-lived tokens and least-privilege IAM roles
- **Environment Isolation**: Maintain strict separation between dev/staging/prod with separate AWS accounts (ideally)
- **No Long-Term Credentials**: Use GitHub OIDC for CI/CD, no hardcoded access keys

### File Organization
- Avoid writing scripts in files, especially for one-time use scripts
- Maintain clear separation between test and production code
- Comment when using placeholder names or values that require user modification

## Terraform Code Style

### Section Headers
Use decorative comment headers to separate logical resource groups:
```hcl
#-------------------- DynamoDB Table --------------------#
#-------------------- Lambda Resources --------------------#
```

### Resource Comments
Add descriptive comments above each resource explaining its purpose:
```hcl
# This DynamoDB table will be used to store website visitor counts.
resource "aws_dynamodb_table" "example_table" {
  # ...
}
```

### Inline Comments
- Use single-line comments for quick explanations above complex configurations
- Start comments with `#` followed by a space
- Use proper capitalization and periods

### Consistent Spacing
Maintain consistent spacing around comment blocks and resource definitions.

## Error Handling

From `docs/error-rules.md`:
- Access `docs/errorlog.md` and update it when encountering errors
- List every error, attempted solution, and the working fix solution
- Review `docs/errorlog.md` before attempting similar fixes

## Terraform Backend Requirements

This project uses **Terraform >= 1.11.0** with S3 native state locking:
```hcl
terraform {
  required_version = ">= 1.11.0"
  
  backend "s3" {
    bucket       = "tf-state-<account>-<region>"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-west-1"
    encrypt      = true
    use_lockfile = true  # Native S3 locking, NO DynamoDB table needed
  }
}
```

## Python Lambda Standards

- Each Lambda should have:
  - `app.py` with main handler function
  - `requirements.txt` for dependencies
  - Proper error handling with try/except blocks
  - Logging using Python logging module (not print statements)
  - Idempotency considerations (can process same event multiple times safely)
  - Environment variable configuration (not hardcoded values)

## Common Anti-Patterns to Avoid

- ❌ Hardcoded values (account IDs, regions, ARNs)
- ❌ Wildcard IAM permissions without justification
- ❌ Missing error handling or DLQs for async operations
- ❌ Mixing test data with production code paths
- ❌ Overwriting .env files without confirmation
- ❌ Creating new patterns when existing ones exist
- ❌ Files exceeding 300 lines without refactoring
- ❌ Long-term AWS credentials in code or CI/CD