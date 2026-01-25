# Repository Structure

## Root Directory Layout

```
AI-DP/
├── .claude/           # Claude Code agent configurations
│   └── agents/        # Specialized agent prompts (portfolio.md)
├── bootstrap/         # Terraform config for S3 state bucket creation
├── dashboard/         # Static HTML/JS dashboard
│   ├── index.html     # Main dashboard page
│   ├── styles.css     # Dashboard styling
│   └── app.js         # Chart.js + AWS SDK integration
├── docs/              # Project documentation
├── envs/              # Environment-specific Terraform configurations
├── lambdas/           # Python Lambda function source code
├── modules/           # Reusable Terraform modules
├── .github/           # GitHub Actions workflows (Phase 10)
├── .gitignore         # Git ignore patterns
├── .mcp.json          # MCP server configuration
├── .terraform-version # Terraform version constraint (1.13.0)
├── CLAUDE.md          # Claude Code guidance file
└── requirements.txt   # Root-level requirements
```

## Environments (`envs/`)

Three environment directories for deployment isolation:
- `envs/dev/` - Development environment (ACTIVE)
- `envs/stg/` - Staging environment
- `envs/prod/` - Production environment

Each environment contains:
- `backend.tf` - S3 backend configuration with native locking
- `providers.tf` - AWS provider configuration with default_tags
- `main.tf` - Root module that wires together modules
- `variables.tf` - Environment-specific variable declarations
- `outputs.tf` - Environment outputs

## Terraform Modules (`modules/`)

Active modules with implementation:

- **`data_lake/`**: S3 bucket with prefixes (raw/, processed/, curated/), lifecycle policies, EventBridge notifications
- **`ingestion_stream/`**: API Gateway HTTP API, Kinesis Data Streams, ETL Lambda, EventBridge rule for batch
- **`step_functions/`**: State machine with Comprehend integration, CloudWatch Logs
- **`hot_store/`**: DynamoDB table with GSI, TTL, PITR
- **`orchestration/`**: Merge Lambda for combining AI outputs
- **`analytics/`**: Glue Crawler, Athena workgroup, results bucket

Standard module structure:
```
modules/<name>/
├── main.tf        # Core infrastructure resources
├── iam.tf         # IAM roles, policies, attachments
├── variables.tf   # Input variables
├── outputs.tf     # Output values
└── README.md      # Module documentation
```

## Lambda Functions (`lambdas/`)

Python-based Lambda function code:

- **`lambdas/etl/`**: Kinesis consumer - validates, normalizes, writes to S3 raw/
  - `app.py` - Main handler (idempotent writes using Kinesis sequence numbers)
  - `requirements.txt` - Python dependencies

- **`lambdas/merge/`**: Merges AI outputs, writes to S3 processed/ and DynamoDB
  - `app.py` - Main handler (~180 lines)
  - `requirements.txt` - Python dependencies

- **`lambdas/replay/`**: DLQ replay utility (future)
  - `app.py` - Main handler
  - `requirements.txt` - Python dependencies

## Dashboard (`dashboard/`)

Static HTML/JS dashboard for analytics visualization:
- `index.html` - Main page structure (header, metrics cards, charts, events table)
- `styles.css` - CSS styling (black/gray theme, responsive design)
- `app.js` - JavaScript with Chart.js + AWS SDK v2 (DynamoDB, S3, Athena queries)
- `config.js` - AWS credentials config (GITIGNORED - local demo only)
- `README.md` - Setup instructions and documentation

**Features:**
- 5 metrics cards: Total records, Positive, Neutral, Negative, Mixed counts
- Sentiment distribution pie chart (Curated S3 - pre-aggregated, instant ~100ms)
- Entity type analysis doughnut chart (Athena with UNNEST - demonstrates SQL skills)
- Recent events table with text preview (first 100 chars)
- Auto-refresh every 60 seconds
- Manual refresh button

**Optimized Data Strategy (2026-01-24):**
| Feature | Data Source | Latency | Why |
|---------|-------------|---------|-----|
| Sentiment Chart | Curated S3 | ~100ms | Pre-aggregated counts by Merge Lambda |
| Total Processed | Curated S3 | ~100ms | Pre-calculated, instant access |
| Entity Chart | Athena | ~3s | Demonstrates UNNEST SQL skill |
| Metrics Cards | DynamoDB | ~50ms | Real-time, last 30 days with TTL |
| Recent Events | DynamoDB | ~50ms | Real-time, last 30 days |

**Why This Optimization:**
- Performance: Sentiment chart loads instantly instead of ~3s
- Cost: Fewer Athena queries = lower cost (Athena charges per data scanned)
- Demonstrates understanding of when to use each AWS service (interview talking point)

## Documentation (`docs/`)

- `roadmap.md` - Detailed implementation roadmap (10 phases)
- `status.md` - Project status tracking
- `errorlog.md` - Historical error log (ALWAYS check before fixing errors)
- `data_flow.md` - Data flow documentation
- `explained.md` - Architecture explanations / Interview walkthrough
- `aws_resources.md` - Comprehensive AWS services guide with interview Q&A
- `ai-dp overview notion.md` - Comprehensive architecture overview

## Module Wiring Pattern

Each environment's `main.tf` instantiates modules and passes outputs:

```hcl
module "data_lake" {
  source = "../../modules/data_lake"
  # ...
}

module "ingestion_stream" {
  source                = "../../modules/ingestion_stream"
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn
  state_machine_arn     = module.step_functions.state_machine_arn
  # ...
}

module "analytics" {
  source                = "../../modules/analytics"
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn
  # ...
}
```
