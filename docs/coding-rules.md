---
inclusion: always
---
# Fundamental Development Principles (Development Directives)
- **NO HARDCODING, EVER**: All solutions must be generic, pattern-based, and work across all commands, not just specific examples.
- **ROOT CAUSE, NOT BANDAID**: Fix the underlying structural or data lineage issues.
- **DATA INTEGRITY**: Use consistent, authoritative data sources (Stage 1 raw JSON for table locations, parsed Stage 3 for final command structure).
- **ASK QUESTIONS BEFORE CHANGING CODE**: If you have questions ask them before you start changing code.
- **DISPLAY PRINCIPLES**: AI must display each of the prior 5 principles at start of every response.

---

# Coding Pattern Preferences

## Code Quality & Simplicity
- Always prefer simple solutions
- Avoid duplication of code whenever possible by checking for existing similar functionality in the codebase
- Keep the codebase clean and organized
- Avoid files over 200–300 lines of code—refactor at that point

## Development Practices
- Write code that accounts for different environments: dev, test, and prod
- Only make changes that are requested or directly related to the requested change
- When fixing bugs, exhaust existing implementation options before introducing new patterns or technologies
- If new patterns are introduced, remove old implementations to prevent duplicate logic
- Avoid building speculative functionality—implement features only when needed
- Comment when using placeholder names or values that require user modification

## Environment & Data Management
- Mock data only for tests, never for dev or prod environments
- Never add stubbing or fake data patterns affecting dev or prod
- Never overwrite `.env` files without asking and confirming first
- Always use up-to-date Terraform resources
- **Security-First Approach**: Prioritize GitHub OIDC authentication over long-term credentials
- **Zero-Trust Principle**: All AWS access must use short-lived tokens and least-privilege IAM roles
- **Environment Isolation**: Maintain strict separation between dev/staging/prod with separate AWS accounts

## File Organization
- Avoid writing scripts in files, especially for one-time use scripts
- Maintain clear separation between test and production code

## Terraform Code Style
- **Section Headers**: Use decorative comment headers to separate logical resource groups
  ```hcl
  #--------------------DynamoDB Table --------------------#
  #--------------------Lambda Resources --------------------#
  ```
- **Resource Comments**: Add descriptive comments above each resource explaining its purpose
  ```hcl
  # This DynamoDB table will be used to store website visitor counts.
  resource "aws_dynamodb_table" "example_table" 
  ```
- **Inline Comments**: Use single-line comments for quick explanations above complex configurations
- **Comment Formatting**: Start comments with `#` followed by a space, use proper capitalization and periods
- **Consistent Spacing**: Maintain consistent spacing around comment blocks and resource definitions