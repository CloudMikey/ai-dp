# Coding Rules Template

> **📋 TEMPLATE FOR FUTURE PROJECTS**
>
> This is a reusable template for establishing coding standards in new projects.
>
> **How to use**:
> 1. Copy the content below into your new project's `CLAUDE.md` or `.claude/` configuration
> 2. Customize the rules based on project type and tech stack
> 3. Remove or modify any rules that don't apply
>
> **Note**: The `inclusion: always` frontmatter below does NOT work in `docs/` directory.
> Claude Code only processes frontmatter in `.claudecontext` files or project root CLAUDE.md.

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
- **Resource Comments**: Add concise comments above resources explaining non-obvious decisions
  ```hcl
  # TTL auto-cleanup reduces storage cost for old events
  resource "aws_dynamodb_table" "events" {
    ttl { ... }
  }
  ```
- **Inline Comments**: Use for complex configurations or justified exceptions (e.g., security tradeoffs)
- **Avoid Decorators**: Resource names are self-documenting; decorator headers add noise
- **Comment Formatting**: Start comments with `#` followed by a space; explain **why**, not **what**