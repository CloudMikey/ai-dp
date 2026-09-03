# Repository Structure

## Root Layout
```
AI-DP/
├── .claude/           # Claude Code configs & agent prompts (portfolio.md)
│   └── commands/      # Slash commands incl. /reset-data (clears dashboard data only)
├── .github/           # GitHub Actions workflows (Phase 10 CI/CD)
├── bootstrap/         # Terraform for S3 state bucket creation
├── dashboard/         # Static analytics dashboard (index.html, styles.css, app.js, config.js)
├── docs/              # Project documentation
│   ├── roadmap.md         # 10-phase implementation roadmap
│   ├── status.md          # Comprehensive project status
│   ├── errorlog.md        # ALWAYS CHECK before fixing errors
│   ├── security-audit-report.md
│   ├── architecture.md        # Mermaid architecture docs + decisions
│   ├── dashboard-explained.md # Plain-language dashboard walkthrough
│   ├── architecture.drawio    # AWS-icon architecture diagram (draw.io)
│   └── ai-dp overview notion.md
├── envs/              # Environment-specific Terraform configs
│   ├── dev/           # ACTIVE environment
│   ├── stg/
│   └── prod/
├── lambdas/           # Python Lambda source
│   ├── etl/           # Kinesis consumer → S3 raw/
│   └── merge/         # Combines AI outputs → S3 processed/ + DynamoDB
├── modules/           # Reusable Terraform modules
│   ├── data_lake/         ├── ingestion_stream/  ├── step_functions/
│   ├── hot_store/         ├── orchestration/     ├── analytics/
│   ├── ai_enrichment/     ├── observability/     └── cost_management/
├── scripts/
│   ├── load_test.py        # Boto3 load tester (25 events default)
│   └── rebuild_summary.py  # Recompute curated summary from DynamoDB (idempotent, --dry-run)
├── test-data/
│   └── batch/         # 8 sample .txt files (3 POS / 3 NEG / 2 MIXED) for batch-path testing
├── CLAUDE.md          # Primary guidance file
├── .terraform-version # Pinned to 1.13.0
├── .tflint.hcl        # TFLint config (snake_case, documented vars/outputs)
└── .tfsec.yml         # Tfsec security scan config
```

## Environment Structure (envs/dev/)
Each env contains: `backend.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`

**Phase 10 addition:**
- `envs/dev/cicd.tf` — GitHub Actions OIDC role (`aws_iam_role.github_actions_dev`) + data source for existing OIDC provider. Inline policy managed via AWS Console (not Terraform).

## Module Standard Structure
```
modules/<name>/
├── main.tf       # Core resources
├── iam.tf        # IAM roles, policies, attachments (SEPARATE from main.tf)
├── variables.tf  # Input variables (all documented)
├── outputs.tf    # Output values (all documented)
└── README.md     # Module documentation
```

## Lambda Standard Structure
```
lambdas/<name>/
├── <name>_handler.py # Handler with try/except, logging module, env vars
├── conftest.py       # pytest fixtures
└── test_<name>.py    # unit tests (excluded from the deployment zip)
```
Packaging is Terraform `archive_file` in `modules/orchestration/main.tf`, which excludes `test_*.py`, `conftest.py`, `__pycache__`, and the previous zip. Deploy a Lambda code change with `terraform -chdir=envs/dev apply` — there is no separate upload step.

## Key Config Files
- `CLAUDE.md` - Claude Code instructions (authoritative)
- `docs/errorlog.md` - Historical errors + solutions (MANDATORY to check before fixing)
- `.tflint.hcl` - Linting rules: snake_case naming, documented vars/outputs, typed variables
- `.tfsec.yml` - Security scanning config
