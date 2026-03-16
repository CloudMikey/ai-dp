# Repository Structure

## Root Layout
```
AI-DP/
├── .claude/           # Claude Code configs & agent prompts (portfolio.md)
├── .github/           # GitHub Actions workflows (Phase 10 CI/CD)
├── bootstrap/         # Terraform for S3 state bucket creation
├── dashboard/         # Static analytics dashboard (index.html, styles.css, app.js, config.js)
├── docs/              # Project documentation
│   ├── roadmap.md         # 10-phase implementation roadmap
│   ├── status.md          # Comprehensive project status
│   ├── errorlog.md        # ALWAYS CHECK before fixing errors
│   ├── security-audit-report.md
│   └── ai-dp overview notion.md
├── envs/              # Environment-specific Terraform configs
│   ├── dev/           # ACTIVE environment
│   ├── stg/
│   └── prod/
├── lambdas/           # Python Lambda source
│   ├── etl/           # Kinesis consumer → S3 raw/
│   ├── merge/         # Combines AI outputs → S3 processed/ + DynamoDB
│   └── replay/        # DLQ replay utility
├── modules/           # Reusable Terraform modules
│   ├── data_lake/         ├── ingestion_stream/  ├── step_functions/
│   ├── hot_store/         ├── orchestration/     ├── analytics/
│   ├── ai_enrichment/     ├── observability/     └── cost_management/
├── scripts/
│   └── load_test.py   # Boto3 load tester (25 events default)
├── CLAUDE.md          # Primary guidance file
├── .terraform-version # Pinned to 1.13.0
├── .tflint.hcl        # TFLint config (snake_case, documented vars/outputs)
└── .tfsec.yml         # Tfsec security scan config
```

## Environment Structure (envs/dev/)
Each env contains: `backend.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`

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
├── app.py            # Handler with try/except, logging module, env vars
└── requirements.txt  # Python dependencies
```

## Key Config Files
- `CLAUDE.md` - Claude Code instructions (authoritative)
- `docs/errorlog.md` - Historical errors + solutions (MANDATORY to check before fixing)
- `.tflint.hcl` - Linting rules: snake_case naming, documented vars/outputs, typed variables
- `.tfsec.yml` - Security scanning config
