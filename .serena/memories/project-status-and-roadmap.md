# AI-DP Project Status & Roadmap

**Last Updated:** 2026-01-29 (Phase 9 Task 4 Complete: CloudWatch Alarms with SNS)

## Current Status: 90% Complete (9 of 10 Phases)

### ✅ Completed Phases

#### Phase 0: Bootstrap Infrastructure
- S3 state bucket: `tf-state-aidp` (us-west-1)
- Terraform 1.13.0 with native S3 locking (`use_lockfile = true`)
- All environments initialized (dev, stg, prod)

#### Phase 1: Data Lake Foundation
**Bucket:** `ai-dp-data-lake-dev-us-west-2`

**Achievements:**
- Three-layer S3 architecture (raw/processed/curated)
- Lifecycle policies with dynamic blocks (avoid empty rule errors)
- Security: SSE-AES256, versioning, public access blocked, TLS enforced
- EventBridge notifications enabled
- Provider `default_tags` pattern (no tag conflicts)

#### Phase 2: Streaming Ingestion Path
**API:** `https://<api-id>.execute-api.us-west-2.amazonaws.com/ingest`

**Components:**
- Kinesis: `ai-dp-dev-ingestion-stream` (1 shard, 24h retention)
- API Gateway HTTP API → Kinesis (direct integration)
- Lambda ETL: `ai-dp-dev-etl` (Python 3.11, 256MB, 60s)
- Event source mapping (batch=100, retry=3)
- SQS DLQ: `ai-dp-dev-etl-dlq` (14-day retention)
- **Idempotent writes:** Kinesis sequence numbers used as S3 filenames (prevents duplicates on retry)

#### Phase 3: Batch Ingestion Path
- EventBridge rule: `ai-dp-dev-s3-batch-ingestion`
- Event pattern: S3 Object Created in `raw/` prefix only
- Outputs: `eventbridge_rule_name`, `eventbridge_rule_arn`

#### Phase 4: Step Functions & EventBridge Wiring
- State machine: `ai-dp-dev-orchestrator`
- EventBridge → Step Functions integration
- CloudWatch Logs: `/aws/states/ai-dp-dev-orchestrator`
- End-to-end batch path: S3 → EventBridge → Step Functions → SUCCESS

#### Phase 5: DynamoDB Hot Store
- Table: `ai-dp-dev-enriched-data`
- Schema: recordId (PK) + timestamp (SK)
- GSI: `timestamp-index` (recordType + timestamp)
- On-demand billing, TTL enabled (30 days), PITR enabled

#### Phase 6: AI Enrichment Services
- Comprehend integration (DetectSentiment + DetectEntities)
- Parallel execution in Step Functions
- S3 read via AWS SDK (no Lambda wrapper needed)
- Verified: sentiment analysis (98.76% confidence), entity extraction

#### Phase 7: Merge Lambda & Complete Orchestration
- Module: `modules/orchestration/`
- Merge Lambda: `lambdas/merge/app.py` (180 lines)
- Dual storage: S3 `processed/` + DynamoDB hot store
- Both streaming and batch paths fully operational
- S3 partitioning: `processed/year=YYYY/month=MM/day=DD/`

#### Phase 8: Analytics & Query Layer ✅ COMPLETE
**Glue & Athena:**
- Glue Database: `ai-dp-dev-analytics`
- Glue Crawler: `ai-dp-dev-crawler` (catalogs `processed/` layer)
- Glue Table: `processed` (13 columns + 3 partition keys)
- Athena Workgroup: `ai-dp-dev-workgroup`
- Athena Results Bucket: `ai-dp-athena-results-dev-us-west-2` (7-day lifecycle)

**Dashboard (HTML/CSS/JS - Browser-Based):**
- Location: `dashboard/` directory
- Tech Stack: Vanilla HTML/CSS/JavaScript + Chart.js v4.4.0 + AWS SDK for JavaScript v2
- Files: `index.html`, `styles.css`, `app.js`, `config.js` (gitignored), `README.md`
- Design: Modern dark theme, responsive (desktop/tablet/mobile)
- Features:
  - 5 real-time metrics cards: Total, Positive, Neutral, Negative, Mixed (DynamoDB)
  - Sentiment distribution pie chart (**Curated S3** - pre-aggregated, instant loading)
  - Entity type analysis doughnut chart (Athena with UNNEST - demonstrates SQL skills)
  - Recent events table (20 most recent from DynamoDB)
  - Pipeline status: Total processed (**Curated S3**), last record time, DLQ health check
  - Auto-refresh every 60 seconds
  - Parallel queries (DynamoDB + S3 + Athena run simultaneously)
- **Optimized Data Sources** (2026-01-24):
  - Sentiment chart: Curated S3 (~100ms) - pre-aggregated by Merge Lambda
  - Total processed count: Curated S3 (~100ms) - pre-calculated
  - Entity type chart: Athena (~3s) - demonstrates UNNEST SQL skill
  - Metrics cards: DynamoDB (~50ms) - real-time, last 30 days
  - Recent events table: DynamoDB (~50ms) - real-time, last 30 days
- Authentication: Local credentials in `config.js` for demo only
- Note: Zero dependencies - runs directly from browser (file system or S3 static hosting)

**Key Achievements:**
- **Dashboard Optimization (2026-01-24):** Moved sentiment chart and total count from Athena to Curated S3 for instant loading
- Three-tier data strategy: Curated S3 (pre-computed aggregates), DynamoDB (real-time hot data), Athena (complex SQL analytics)
- Demonstrates understanding of when to use each AWS service (interview talking point)
- Glue Crawler + Athena for SQL analytics on processed layer
- Partition pruning reduces Athena costs by 90%+
- Browser-based dashboard: Zero installation, no server needed
- Simple to demo in portfolio (open index.html in browser)
- Entity analysis with UNNEST: Tracks ORGANIZATION, PERSON, LOCATION, DATE, etc.
- Responsive design: 5-column (desktop), 3-column (tablet), 2-column (mobile)

### 🔄 Next Phase

#### Phase 9: Production Hardening (44% Complete - 4/9 tasks)
**Goal:** Load testing, security review, monitoring, operational documentation

**Completed Tasks:**
1. ✅ Lambda unit tests (pytest + moto) - 33 tests, 96% coverage
2. ✅ Load testing streaming path - 1000 events, 0% errors, P95 < 2s
3. ✅ CloudWatch Dashboard - `ai-dp-dev-operations` with 8 widgets
4. ✅ CloudWatch Alarms with SNS notifications:
   - SNS Topic: `ai-dp-dev-cloudwatch-alarms` (email subscription)
   - 6 alarms: Lambda error rate (2), DLQ depth (2), Kinesis iterator age (1), Step Functions failures (1)
   - Metric math for Lambda error rate: `(errors/invocations)*100`
   - All alarms use `treat_missing_data = "notBreaching"`
   - Email alerts tested and verified working

**Remaining Tasks:**
5. Security review (IAM audit, tfsec scan)
6. Cost optimization review
7. Architecture documentation
8. Operational runbooks
9. Staging environment deployment

### 📋 Remaining Phases

- Phase 9: Production Hardening
- Phase 10: CI/CD Pipeline (GitHub Actions with OIDC)

## Key Infrastructure Outputs

```hcl
data_lake_bucket_name     = "ai-dp-data-lake-dev-us-west-2"
kinesis_stream_name       = "ai-dp-dev-ingestion-stream"
api_gateway_invoke_url    = "https://<api-id>.execute-api.us-west-2.amazonaws.com/ingest"
eventbridge_rule_name     = "ai-dp-dev-s3-batch-ingestion"
state_machine_arn         = "arn:aws:states:us-west-2:<account-id>:stateMachine:ai-dp-dev-orchestrator"
dynamodb_table_name       = "ai-dp-dev-enriched-data"
glue_database_name        = "ai-dp-dev-analytics"
athena_workgroup_name     = "ai-dp-dev-workgroup"
```

## Module Structure

```
modules/
├── data_lake/           # Phase 1 - S3 + EventBridge notifications
├── ingestion_stream/    # Phase 2 & 3 - API Gateway + Kinesis + Lambda + EventBridge
├── step_functions/      # Phase 4 - State machine orchestration
├── hot_store/           # Phase 5 - DynamoDB tables
├── orchestration/       # Phase 7 - Merge Lambda
├── analytics/           # Phase 8 - Glue + Athena
└── observability/       # Phase 9 - CloudWatch Dashboard + Alarms + SNS
```

## Development Commands

```powershell
# Terraform workflow
terraform -chdir=envs/dev fmt
terraform -chdir=envs/dev validate
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev apply

# Test streaming ingestion
curl -X POST "https://<api-id>.execute-api.us-west-2.amazonaws.com/ingest" `
  -H "Content-Type: application/json" `
  -H "X-Partition-Key: test-key" `
  -d '{"event_type":"test","event_timestamp":"2026-01-24T12:00:00Z"}'

# Test batch ingestion
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json

# Run Glue Crawler
aws glue start-crawler --name ai-dp-dev-crawler --region us-west-2

# Query via Athena
aws athena start-query-execution --query-string "SELECT * FROM processed LIMIT 10" \
  --work-group ai-dp-dev-workgroup --region us-west-2
```

## Important Lessons Learned

1. **Tag Conflicts:** Use provider `default_tags` for global tags; modules add resource-specific tags only
2. **Lifecycle Rules:** Use dynamic blocks with `for_each` to avoid empty rule errors
3. **IAM Least Privilege:** Scope S3 permissions to specific prefixes (e.g., `raw/*`)
4. **EventBridge Filtering:** Always filter to specific prefix to prevent infinite loops
5. **Idempotent Writes:** Use Kinesis sequence numbers as S3 filenames to prevent duplicates on retry
6. **Dashboard Strategy:** Static HTML/JS dashboard avoids server dependencies; use Cognito for production auth
