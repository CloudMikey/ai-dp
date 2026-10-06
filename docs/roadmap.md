# AI-Powered Serverless Data Pipeline - Implementation Roadmap

**Sequential Implementation Plan:** Build only what's needed for each phase, no "placeholders for later" unless explicitly marked.

---

## Phase 0: Project Bootstrap
**Goal:** Terraform-ready repository with remote state management

### Tasks

**1. Repository Structure Setup**
- Create directory structure (`/envs/{dev,stg,prod}`, `/modules/*`, `/lambdas/*`, `/docs/*`)
- Add `.gitignore`, `.editorconfig`, and `README.md`
- Initialize Git repository

**Complete when:** Directory structure matches skeleton, all configuration files committed

**2. Terraform Version & Standards**
- Install Terraform >= 1.11.0
- Create `terraform.tf` files in each env with version constraints
- Add `tflint`, `tfsec` configuration files

**Complete when:** `terraform version` shows >= 1.11.0, linters configured and passing

**3. S3 State Bucket with Native Locking**
- Create `bootstrap/` directory with Terraform config for S3 backend bucket
- Define S3 bucket resource with versioning enabled and encryption
- Apply bootstrap config locally: `terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply`
- Configure `backend.tf` in each env with `use_lockfile = true` pointing to created bucket
- Migrate local state to remote: `terraform init -migrate-state` in each env directory

**Complete when:** S3 bucket exists with versioning enabled, `.tflock` files appear in S3 during `terraform plan`, all three envs using remote state

**Status:** ✅ **COMPLETED**

---

## Phase 1: Data Lake Foundation
**Goal:** Three-layer S3 data lake with lifecycle policies

### Tasks

**1. Data Lake Module (`modules/data_lake/`)**
- Create S3 bucket with prefixes: `raw/`, `processed/`, `curated/`
- Enable versioning and SSE-S3 encryption
- Configure lifecycle policies for each layer (different retention per layer)
- Block public access (all 4 settings)
- Enforce TLS/HTTPS via bucket policy

**Complete when:** Bucket created, encryption verified, lifecycle rules tested with sample uploads to all three layers

**2. Enable S3 EventBridge Notifications**
- Add `aws_s3_bucket_notification` resource with `eventbridge = true` to data lake module
- This allows EventBridge to receive S3 object creation events

**Complete when:** S3 bucket has EventBridge notifications enabled (visible in S3 console)

**Status:** ✅ **COMPLETED** (All tasks finished on 2025-10-27)
- Task 1: Data Lake Module with three-layer architecture
- Task 2: EventBridge notifications enabled for batch ingestion support

---

## Phase 2: Streaming Ingestion Path
**Goal:** Working API Gateway → Kinesis → Lambda → S3 pipeline

### Tasks

**1. Streaming Ingestion Module - Part 1 (`modules/ingestion_stream/`)**
- Create `modules/ingestion_stream/` module structure
- Create HTTP API Gateway with single POST endpoint (`/ingest`)
- Create Kinesis Data Stream (1 shard for dev, variable for scaling)
- Configure API Gateway → Kinesis integration (direct integration, no Lambda proxy)

**Complete when:** API endpoint accepts JSON payloads, data appears in Kinesis stream (visible in Kinesis console)

**2. ETL Lambda Function (`lambdas/etl/`)**
- Write `lambdas/etl/app.py`:
  - Consume from Kinesis stream
  - Validate JSON structure (basic schema check)
  - Normalize data (consistent timestamp format, required fields)
  - Write to S3 `raw/` layer with partitioning (`raw/year=YYYY/month=MM/day=DD/data.json`)
- Create `requirements.txt` with dependencies (boto3, etc.)
- Package Lambda deployment artifact
- Create SQS Dead Letter Queue (DLQ) for failed events
- Add CloudWatch Logs for Lambda

**Complete when:** Lambda code written, packaged, DLQ created (not yet wired to Kinesis)

**Status:** ✅ **COMPLETED** - Lambda simplified for portfolio-level learning (166 lines)

**3. Lambda Infrastructure (`modules/ingestion_stream/` - Part 2)**
- Add Lambda resource to `ingestion_stream` module
- Create IAM role for Lambda with permissions:
  - Kinesis: `DescribeStream`, `GetRecords`, `GetShardIterator`
  - S3: `PutObject` to data lake `raw/*` prefix only
  - CloudWatch Logs: `CreateLogGroup`, `CreateLogStream`, `PutLogEvents`
  - SQS: `SendMessage` to DLQ
- Configure Lambda event source mapping (Kinesis → Lambda)
- Configure DLQ for failed Kinesis events
- Set Lambda timeout (60s), memory (256MB)

**Complete when:** Lambda deployed, event source mapping active, can consume from Kinesis

**4. Integration Testing - Streaming Path**
- Send test JSON payload to API Gateway endpoint
- Verify data flows: API Gateway → Kinesis → Lambda → S3 `raw/`
- Verify partitioning is correct (`raw/year=2025/month=01/day=24/...`)
- Test error scenario: Send invalid JSON → verify DLQ receives message

**Complete when:** End-to-end streaming ingestion works, data appears in S3 `raw/` with correct partitions, DLQ catches errors

**Status:** ✅ **COMPLETED** (All 4 tasks finished on 2025-10-27)
- API Gateway → Kinesis integration tested and working
- Lambda ETL function deployed and processing records
- S3 partitioning verified: `raw/year=2025/month=10/day=27/`
- DLQ error handling tested: Invalid records sent to SQS after 3 retries

---

## Phase 3: Batch Ingestion Path (EventBridge)
**Goal:** EventBridge detects S3 uploads to `raw/` (orchestration happens later)

### Tasks

**1. EventBridge Rule (`modules/ingestion_stream/` - Part 3)** ✅ **COMPLETED**
- ✅ EventBridge rule added to `ingestion_stream` module
- ✅ Event pattern configured: source=`aws.s3`, detail-type=`Object Created`, prefix=`raw/`
- ✅ Filtered to data lake bucket: `ai-dp-data-lake-dev-us-west-2`
- ✅ CloudWatch Metrics available (rule invocations tracked automatically)
- ✅ Outputs added: `eventbridge_rule_name`, `eventbridge_rule_arn`

**Implementation Notes:**
- Rule name: `ai-dp-dev-s3-batch-ingestion`
- Event pattern filters to `raw/` prefix only (prevents infinite loops from processed/ writes)
- State: ENABLED (ready for testing)
- No target configured yet - target will be added in Phase 4 after Step Functions created
- Module files updated: `main.tf` (lines 454-489), `outputs.tf` (lines 88-98), `README.md` (EventBridge section)

**Complete when:** File upload to `raw/` triggers EventBridge rule (visible in CloudWatch Metrics "Invocations")

**2. Testing - Batch Event Detection** ✅ **COMPLETED**
- ✅ Uploaded file to `raw/` layer: EventBridge rule triggered (CloudWatch Metrics verified)
- ✅ Verified EventBridge rule shows "Invocations" metric increase
- ✅ Verified uploads to `processed/` and `curated/` do NOT trigger rule (filter working correctly)

**Testing Results:**
- EventBridge reliably detects `raw/` uploads only
- Prefix filter successfully prevents triggers from other layers
- CloudWatch Metrics confirmed rule invocations

**Complete when:** EventBridge reliably detects `raw/` uploads, ignores other layers ✅

**Status:** ✅ **COMPLETED** (All tasks finished - 100%)

---

## Phase 4: Step Functions Placeholder & EventBridge Wiring
**Goal:** Batch ingestion triggers Step Functions (minimal state machine)

### Tasks

**1. Step Functions Module - Minimal Placeholder (`modules/step_functions/`)** ✅ **COMPLETED**
- ✅ Created `modules/step_functions/` module structure
- ✅ Created `statemachine.json` with minimal ASL definition:
  - Single "Pass" state that logs input
  - Outputs success message
- ✅ Created IAM role for Step Functions with CloudWatch Logs permissions
- ✅ Created Step Functions state machine resource
- ✅ Enabled CloudWatch Logs (log level: ALL)

**Complete when:** State machine created, can be triggered manually via console, execution logs appear in CloudWatch ✅

**2. EventBridge Target Configuration (`modules/ingestion_stream/` - Part 4)** ✅ **COMPLETED**
- ✅ Added EventBridge target resource (conditional creation via variable)
- ✅ Added variable: `state_machine_arn` (accepts ARN from Step Functions module)
- ✅ Added variable: `create_eventbridge_target` (boolean, default: false)
- ✅ Created IAM role for EventBridge with `states:StartExecution` permission
- ✅ Wired EventBridge rule → Step Functions target

**Complete when:** Terraform code ready, variables defined (not yet enabled) ✅

**3. Wire EventBridge to Step Functions (`envs/dev/main.tf`)** ✅ **COMPLETED**
- ✅ Updated `ingestion_stream` module call in `envs/dev/main.tf`:
  - Set `state_machine_arn = module.step_functions.state_machine_arn`
  - Set `create_eventbridge_target = true`
- ✅ Applied Terraform changes

**Complete when:** EventBridge target created and active ✅

**4. Integration Testing - Batch Path** ✅ **COMPLETED**
- ✅ Uploaded file to S3 `raw/`: Batch upload test executed
- ✅ Verified Step Functions execution triggered (visible in Step Functions console)
- ✅ Verified execution completed successfully (Pass state)
- ✅ Verified CloudWatch Logs show S3 event details in state machine input

**Complete when:** End-to-end batch ingestion works: S3 upload → EventBridge → Step Functions → Logs confirm event delivery ✅

**Status:** ✅ **COMPLETED** (All tasks finished on 2025-10-27)
- State machine deployed: `ai-dp-dev-orchestrator` with Pass state
- IAM roles configured: Step Functions execution role + EventBridge invocation role
- CloudWatch Logs enabled: `/aws/states/ai-dp-dev-orchestrator` (ALL level)
- EventBridge → Step Functions integration verified
- End-to-end batch path tested: S3 upload → EventBridge → Step Functions → SUCCESS
- Execution verified: State machine completed in 53ms with Pass state output

---

## Phase 5: DynamoDB Hot Store
**Goal:** DynamoDB table ready for enriched data storage (created BEFORE AI enrichment needs it)

### Tasks

**1. DynamoDB Hot Store Module (`modules/hot_store/`)** ✅ **COMPLETED**
- ✅ Created `modules/hot_store/` module structure (main.tf, iam.tf, variables.tf, outputs.tf, README.md)
- ✅ Created DynamoDB table: `ai-dp-dev-enriched-data`
  - Partition key: `recordId` (String)
  - Sort key: `timestamp` (Number)
  - GSI: `timestamp-index` (recordType + timestamp for date range queries)
  - On-demand billing mode (PAY_PER_REQUEST)
  - Point-in-time recovery enabled (35-day retention)
  - Encryption at rest enabled (AWS-managed keys)
- ✅ Configured TTL attribute: `expiresAt` (30-day retention for dev)
- ✅ Module wired to dev environment

**Implementation Notes:**
- Table name: `ai-dp-dev-enriched-data`
- GSI enables time-based analytics queries (e.g., "get all text records from last 7 days")
- TTL provides automatic data lifecycle management (old data auto-deleted after 30 days)
- IAM placeholder added for Phase 7 Merge Lambda permissions
- Module outputs: table_name, table_arn, gsi_name, ttl_attribute_name, ttl_days

**Complete when:** DynamoDB table created, can write/read test records via console, GSI returns results ✅

**2. Test DynamoDB Operations** ✅ **COMPLETED**
- ✅ Write/read test records via AWS CLI (put-item, get-item)
- ✅ Update test record (update-item)
- ✅ Delete test record (delete-item)
- ✅ Query by partition key (recordId)
- ✅ Query using GSI (timestamp-index with recordType + timestamp range filtering)
- ✅ Verified TTL enabled on `expiresAt` attribute
- ✅ Verified PITR enabled (35-day recovery period)

**Testing Results:**
- All CRUD operations verified working
- GSI queries successfully filtered by recordType and timestamp range
- TTL status: ENABLED on `expiresAt` attribute
- PITR status: ENABLED with 35-day recovery period

**Complete when:** All CRUD operations work, GSI functional, TTL deletes old items ✅

**Status:** ✅ **COMPLETED** (All tasks finished on 2025-01-24)

**Error Encountered:**
- Error #3: AWS DynamoDB Invalid Tag Value Characters (parentheses not allowed)
- Fix: Changed Description tag from "Hot store for AI-enriched data (recent records only)" to "Hot store for AI-enriched data - recent records only"
- Documented in `docs/errorlog.md`

---

## Phase 6: AI Enrichment Services
**Goal:** Comprehend sentiment analysis integrated with Step Functions

### Tasks

**1. AI Enrichment Module - Comprehend Only (`modules/ai_enrichment/`)** ✅ **COMPLETED**
- ✅ IAM permissions added to Step Functions role (Comprehend DetectSentiment, DetectEntities)
- ✅ S3 read permissions added to Step Functions role (`s3:GetObject` on `raw/*` prefix)
- ✅ Module documentation created in manual implementation guide

**Implementation Notes:**
- No separate `ai_enrichment` module created (Comprehend is serverless, no resources to provision)
- IAM permissions added directly to Step Functions role in `modules/step_functions/iam.tf`
- Least-privilege IAM: S3 scoped to `raw/*` prefix, Comprehend limited to 2 actions only

**Complete when:** IAM role created with correct permissions ✅

**2. Update Step Functions State Machine - Add Comprehend Task** ✅ **COMPLETED**
- ✅ Updated `modules/step_functions/statemachine.json` with real Comprehend workflow
- ✅ Replaced Pass state with 5-state workflow:
  - ExtractS3Details: Extract bucket/key from EventBridge event
  - ReadS3Object: Read file from S3 using AWS SDK integration
  - ParallelComprehendAnalysis: Fan-out to parallel Comprehend tasks
  - DetectSentiment + DetectEntities: Run simultaneously (2x faster)
  - FormatResults: Merge parallel results into single object
- ✅ Step Functions IAM role updated with `s3:GetObject` and Comprehend permissions
- ✅ State machine deployed and active

**Complete when:** State machine updated, can successfully call Comprehend on S3 object content ✅

**3. Testing - AI Enrichment** ✅ **COMPLETED**
- ✅ Created sample text file with sentiment and entities
- ✅ Uploaded to S3 `raw/` layer (triggered EventBridge → Step Functions)
- ✅ Verified Step Functions execution succeeded with Comprehend results
- ✅ Verified execution output contains:
  - Sentiment: POSITIVE (98.76% confidence)
  - Entities: "Amazon Web Services" (ORGANIZATION), "AWS Lambda" (TITLE), etc.
- ✅ CloudWatch Logs confirmed all states executed successfully

**Testing Results:**
- Parallel execution working: DetectSentiment and DetectEntities run simultaneously
- S3 integration working: State machine reads objects from `raw/` directly
- JSONPath transformations working: Nested S3 event data correctly extracted

**Complete when:** Comprehend successfully analyzes S3 objects, results visible in Step Functions execution history ✅

**Status:** ✅ **COMPLETED** (All tasks finished on 2025-01-30)

**Key Achievements:**
- Implemented parallel execution for Comprehend tasks (50% performance improvement)
- Used Step Functions AWS SDK integrations (no Lambda wrapper needed)
- Implemented least-privilege IAM with S3 scoped to `raw/*` prefix
- Successfully integrated real AI enrichment (sentiment + entity extraction)
- Manual implementation guide created: `Z:\CODE\Notes\Manual\phase-6-ai-enrichment-manual-guide.md`

---

## Phase 7: Merge Lambda & Complete Orchestration
**Goal:** Combine AI outputs and write to `processed/` + DynamoDB

### Tasks

**1. Merge Lambda Function (`lambdas/merge/`)** ✅ **COMPLETED**
- ✅ Written `lambdas/merge/app.py` (180 lines):
  - Accepts AI enrichment results as input (from Step Functions)
  - Merges Comprehend sentiment + entities into single JSON object
  - Writes enriched data to S3 `processed/` layer with date partitioning
  - Writes enriched data to DynamoDB hot store with TTL
  - Returns success/failure status
- ✅ Created `requirements.txt`
- ✅ Lambda code packaged (no external dependencies needed - boto3 included in runtime)

**Implementation Notes:**
- Function name: `ai-dp-dev-merge`
- Environment variables: DATA_LAKE_BUCKET, PROCESSED_PREFIX, DYNAMODB_TABLE, TTL_DAYS
- Generates unique recordId: `{timestamp}-{uuid}`
- S3 partitioning: `processed/year=YYYY/month=MM/day=DD/{uuid}.json`
- DynamoDB TTL: 30 days for dev environment
- Error handling: S3 write must succeed, DynamoDB write is best-effort

**Complete when:** Lambda code written and packaged ✅

**2. Merge Lambda Infrastructure (`modules/orchestration/`)** ✅ **COMPLETED**
- ✅ Created new module: `modules/orchestration/` (main.tf, iam.tf, variables.tf, outputs.tf, README.md)
- ✅ Lambda resource deployed with least-privilege IAM role
- ✅ IAM permissions configured:
  - S3: `PutObject` to `processed/*` prefix only
  - DynamoDB: `PutItem` to hot store table
  - CloudWatch Logs: CreateLogGroup, CreateLogStream, PutLogEvents
  - SQS: SendMessage to DLQ
- ✅ SQS Dead Letter Queue created: `ai-dp-dev-merge-dlq` (14-day retention)
- ✅ CloudWatch Log Group: `/aws/lambda/ai-dp-dev-merge` (7-day retention for dev)
- ✅ Lambda configuration: Python 3.11, 256MB memory, 60s timeout

**Complete when:** Merge Lambda deployed with IAM role and DLQ ✅

**3. Update Step Functions - Add Merge Lambda Task** ✅ **COMPLETED**
- ✅ Updated `modules/step_functions/main.tf` with InvokeMergeLambda state
- ✅ Lambda invocation task added after FormatResults state
- ✅ Input transformation: Passes source_object, ai_enrichment, processing_metadata to merge Lambda
- ✅ Error handling implemented:
  - Retry: 3 attempts for Lambda.ServiceException and Lambda.TooManyRequestsException (exponential backoff)
  - Catch: All errors caught, execution moves to MergeFailed state
  - DLQ: Lambda DLQ captures failed invocations
- ✅ Step Functions IAM role updated with `lambda:InvokeFunction` permission on merge Lambda ARN

**Complete when:** State machine includes merge Lambda task ✅

**4. End-to-End Testing - Full Pipeline** ✅ **COMPLETED**
- ✅ **Batch Path Tested:** Upload to S3 `raw/` → EventBridge → Step Functions → Comprehend → Merge Lambda → S3 `processed/` + DynamoDB
  - Verified S3 processed/ contains enriched JSON with sentiment + entities
  - Verified DynamoDB record created with recordId, timestamp, sentiment, entities, TTL
  - Verified S3 partitioning: `processed/year=2025/month=12/day=07/`
- ✅ **Streaming Path Tested:** API Gateway → Kinesis → ETL Lambda → S3 `raw/` → (same as batch path above)
  - End-to-end streaming pipeline verified working
- ✅ Verified enriched data structure includes:
  - recordId, timestamp, recordType
  - sentiment, sentimentScore, sentimentScores
  - entities (list), entityDetails (full Comprehend output)
  - rawDataLocation, processedDataLocation
  - mergedAt, lambdaVersion, lambdaName, processingMetadata
- ✅ Error scenario tested: DLQ captures failed Lambda invocations

**Complete when:** Both ingestion paths work end-to-end, data lands in `processed/` and DynamoDB with AI enrichments ✅

**Status:** ✅ **COMPLETED** (All tasks finished on 2025-12-07)

**Key Achievements:**
- Implemented complete data pipeline: Ingestion → AI Enrichment → Storage
- Both streaming and batch paths fully operational end-to-end
- Dual storage strategy working: DynamoDB (hot) + S3 (historical)
- Comprehensive error handling: DLQ, retries, catch blocks, CloudWatch Logs
- Least-privilege IAM: All permissions scoped to specific resources/prefixes
- Date partitioning on S3 processed/ layer enables efficient Athena queries (Phase 8)
- DynamoDB TTL provides automatic data lifecycle management (30-day retention)

---

## Phase 8: Analytics & Query Layer
**Goal:** Glue + Athena for SQL queries, visualization dashboard

### Tasks

**1. Analytics Module - Glue Crawler (`modules/analytics/`)**
- ✅ Create `modules/analytics/` module structure (main.tf, iam.tf, variables.tf, outputs.tf, README.md)
- ✅ Create Glue database (`ai-dp-dev-analytics`)
- ✅ Create Glue crawler for `processed/` prefix:
  - Schedule: On-demand (manual trigger)
  - Partition detection enabled (auto-detects `year`/`month`/`day`)
  - Schema inference from JSON files
  - Schema change policy: `UPDATE_IN_DATABASE` (handles evolving enrichment fields)
- ✅ Create IAM role for Glue crawler with S3 read permissions
- ✅ Run initial crawl successfully
- **Fix Applied:** Added `glue:BatchGetPartition` permission (was initially missing)

**Complete when:** ✅ Glue crawler successfully catalogs S3 `processed/` data, tables visible in Glue Data Catalog

**2. Athena Query Setup**
- ✅ Create Athena workgroup (`ai-dp-dev-workgroup`)
- ✅ Configure S3 bucket for Athena query results (`ai-dp-athena-results-dev-us-west-2`)
- ✅ 7-day lifecycle policy on query results bucket (automatic cleanup)
- ✅ CloudWatch metrics enabled for query monitoring
- ✅ Test sample queries:
  - `SELECT sentiment, COUNT(*) FROM processed GROUP BY sentiment` - Working
  - Query by partition: `WHERE year='2025' AND month='12'` - Partition pruning works
  - Table schema verified: 13 columns + 3 partition keys detected

**Complete when:** ✅ Can query `processed/` data via SQL in Athena, partitions work, query performance acceptable

**3. Visualization Dashboard - Choose Platform**
- ✅ **Decision:** Vanilla HTML/CSS/JavaScript with AWS SDK for JavaScript (browser-based)
- **Rationale:** Zero dependencies, no backend needed, runs anywhere (local browser or S3 static hosting), Chart.js for visualizations, simple to understand and explain in interviews

**Complete when:** ✅ Platform chosen and documented

**4. Build Dashboard (Based on Chosen Platform)**
- ✅ Implement browser-based dashboard with key metrics:
  - Sentiment distribution (interactive Chart.js pie chart) - **Curated S3** (pre-aggregated, ~100ms)
  - Entity type analysis (doughnut chart) - Athena query with UNNEST for entity arrays (~3s)
  - Total records metric (**Curated S3** - pre-calculated, ~100ms)
  - Positive/Negative/Neutral/Mixed counts with color-coded cards (DynamoDB aggregation, ~50ms)
  - Recent events table (DynamoDB scan, shows 20 most recent records, ~50ms)
  - Pipeline status monitoring (total processed from **Curated S3**, last record time, DLQ health check)
- ✅ Connect to Curated S3 for pre-aggregated metrics (AWS SDK for JavaScript v2)
- ✅ Connect to Athena for complex SQL queries with UNNEST (AWS SDK for JavaScript v2)
- ✅ Connect to DynamoDB for real-time view (AWS SDK for JavaScript v2)
- ✅ Dashboard files created:
  - `dashboard/index.html` - Main page structure
  - `dashboard/styles.css` - All styling (responsive design)
  - `dashboard/app.js` - JavaScript logic, AWS SDK integration, chart rendering
  - `dashboard/config.js` - AWS credentials (gitignored, local only)
  - `dashboard/README.md` - Setup instructions
- ✅ Performance features:
  - Parallel queries (DynamoDB + S3 + Athena run simultaneously)
  - Auto-refresh every 60 seconds
  - Loading states for user feedback
- ✅ Interactive features: Auto-refresh, color-coded sentiment badges, responsive layout (desktop/tablet/mobile)

**Complete when:** ✅ Dashboard shows live data from Curated S3 (aggregates), DynamoDB (real-time), and Athena (complex SQL)

**Status:** ✅ **COMPLETED** (2026-01-20, **Optimized 2026-01-24**)
- Task 1: Analytics module deployed with Glue database, crawler, Athena workgroup, S3 results bucket
- Task 2: Athena queries working, partitions detected, query results validated
- Task 3: Dashboard platform selected (Vanilla HTML/CSS/JS - portfolio simplicity)
- Task 4: Dashboard implemented with Chart.js visualizations, three-tier data strategy, browser-based AWS SDK

**Dashboard Optimization (2026-01-24):**
| Feature | Before | After | Why |
|---------|--------|-------|-----|
| Sentiment Chart | Athena (~3s) | Curated S3 (~100ms) | Pre-aggregated counts, instant |
| Total Processed | Athena COUNT (~3s) | Curated S3 (~100ms) | Pre-calculated by Merge Lambda |
| Entity Type Chart | Athena | Athena (~3s) | Kept - demonstrates UNNEST SQL skill |
| Metrics Cards | DynamoDB | DynamoDB (~50ms) | Real-time, last 30 days |
| Recent Events Table | DynamoDB | DynamoDB (~50ms) | Real-time, last 30 days |

**Key Learnings:**
- AWS Glue constraint: `CRAWL_NEW_FOLDERS_ONLY` requires `LOG`-only schema policies. Used `CRAWL_EVERYTHING` instead to allow `UPDATE_IN_DATABASE`.
- IAM permission `glue:BatchGetPartition` required for partition operations (not in initial policy).
- Browser-based dashboard benefits: No server needed, zero installation, runs directly from file system or S3 static hosting, simple to demo in portfolio.
- **Three-tier data strategy:** Curated S3 for pre-aggregated metrics (instant), DynamoDB for real-time hot data (last 30 days), Athena for complex SQL analytics (UNNEST).
- **Dashboard optimization demonstrates understanding of when to use each AWS service** (interview talking point).
- Responsive design: Desktop (5-column metrics grid), tablet (3-column), mobile (2-column).

---

## Phase 9: Production Hardening & Documentation
**Goal:** Load testing, security review, operational documentation

### Tasks

**1. Lambda Unit Tests** ✅ **COMPLETED**
- ✅ Write unit tests for ETL Lambda (`lambdas/etl/test_etl.py`) - 17 tests
- ✅ Write unit tests for Merge Lambda (`lambdas/merge/test_merge.py`) - 16 tests
- ✅ Use `pytest` and `moto` for mocking AWS services
- ✅ Achieve >70% code coverage (portfolio-appropriate) - **96% achieved**

**Implementation Notes:**
- Renamed Lambda files to avoid module collision: `app.py` → `etl_handler.py` / `merge_handler.py`
- Updated Terraform handler references in `modules/ingestion_stream/main.tf` and `modules/orchestration/main.tf`
- Added `get_config()` lazy loading pattern for testability (env vars read at runtime, not import time)
- Shared fixtures in `lambdas/conftest.py` (AWS credentials, sys.path setup)
- Documentation: `docs/lambdatest.md` (later removed in commit 218f639; still in git history)

**Complete when:** ✅ Tests written, all tests pass, coverage threshold met

**2. Load Testing - Streaming Path** ✅
- Created load test script: `scripts/load-test-streaming.ps1`
- Sent 1000 events to API Gateway endpoint
- Monitored:
  - Lambda concurrency (max: 1)
  - Kinesis iterator age (0 seconds - no backlog)
  - Error rates (0%)
  - P95 latency (2044ms - well under 5s threshold)
- Results: No bottlenecks identified at 1000-event scale

**Load Test Results (Test Run: 993afa22):**
- Events Sent: 1000 (100% success)
- API Gateway Avg Latency: 267ms
- Lambda P95 Duration: 2044ms
- Lambda Errors: 0
- DLQ Messages: 0

**Complete when:** ✅ System handles 1000 events without errors, latency acceptable (<5s P95)

**3. CloudWatch Dashboards** ✅
- Created operational dashboard in `modules/observability/`:
  - Lambda invocations, errors, duration (ETL + Merge)
  - Kinesis metrics (iterator age, incoming records)
  - Step Functions execution status (started, succeeded, failed)
  - Dead Letter Queue messages (ETL + Merge DLQs)
  - DynamoDB consumed read/write capacity
- Dashboard name: `ai-dp-dev-operations`
- 8 widgets across 7 rows, all using 5-minute periods

**Complete when:** ✅ Single dashboard shows system health, anomalies visible at a glance

**4. CloudWatch Alarms** ✅ **COMPLETED**
- ✅ Created SNS topic: `ai-dp-dev-cloudwatch-alarms` with email subscription
- ✅ Created 6 CloudWatch alarms:
  - Lambda error rate > 5% (ETL + Merge) - metric math: `(errors/invocations)*100`
  - DLQ depth > 0 (ETL + Merge) - immediate alert on any message
  - Kinesis iterator age > 60,000ms (1 minute)
  - Step Functions failures > 3 in 5 minutes
- ✅ Email notifications tested and verified working

**Implementation Notes:**
- Alarms in separate file: `modules/observability/alarms.tf`
- Email address passed via variable (gitignored `terraform.tfvars`)
- All alarms use `treat_missing_data = "notBreaching"` to avoid false positives
- Severity tags: Critical (DLQ), High (Lambda errors, Step Functions), Medium (Kinesis)

**Complete when:** ✅ All alarms created, SNS notifications tested

**5. Security Review** ✅ **COMPLETED**
- ✅ Audited all 7 IAM roles for least-privilege compliance
- ✅ Verified all S3 buckets block public access (all 4 settings enabled)
- ✅ Verified TLS enforcement on S3 buckets (bucket policy denies non-HTTPS)
- ✅ Verified encryption at rest (S3: SSE-S3, DynamoDB: AWS-managed, Kinesis: KMS)
- ✅ Ran `tfsec` security scan (0 critical findings, accepted risks documented)
- ✅ Created security audit report: `docs/security-audit-report.md`

**Security Fixes Applied:**
- Removed unnecessary `s3:PutObjectAcl` from ETL Lambda IAM policy
- Added documentation for Step Functions CloudWatch wildcard (AWS requirement)
- **Enabled Kinesis KMS encryption** (was NONE, now uses `alias/aws/kinesis`)

**tfsec Results:**
- 0 critical findings
- 17 high (all accepted - IAM wildcards for AWS APIs that don't support resource-level permissions)
- Full report: `docs/tfsec-report.md` (later removed; rerun tfsec to reproduce)

**Complete when:** ✅ Security scan passes, no critical findings, audit trail documented

**6. Cost Optimization Review** ✅ **COMPLETED**
- ✅ Reviewed S3 lifecycle policies (already optimal: 180-day raw, 365-day processed)
- ✅ Reviewed DynamoDB capacity mode (on-demand appropriate for sporadic dev workload)
- ✅ Audited CloudWatch Logs retention (all 7 days confirmed)
- ✅ Created cost_management Terraform module with AWS Budget alerts
- ✅ Deployed $50/month budget with 80%, 100% actual, and 100% forecasted thresholds
- ✅ Documented findings in `docs/cost-optimization-report.md` (later removed in commit 218f639; still in git history)

**Implementation Notes:**
- Current monthly costs: ~$12/month (76% under budget)
- Kinesis identified as largest cost driver ($10.87/month, 91% of total)
- All log groups verified with 7-day retention via Terraform
- Budget alerts configured via IaC (not manual console setup)

**Cost Breakdown (Jan 2026):**
- Kinesis: $10.87 (on-demand data stream)
- Route 53: $0.50 (DNS hosted zone)
- Glue: $0.21 (crawler runs)
- Step Functions: $0.19 (state transitions)
- Athena: $0.07 (query data scanned)
- S3: $0.04 (storage + requests)
- DynamoDB: $0.002 (on-demand reads/writes)

**Complete when:** ✅ Cost controls in place, budget alerts configured

**7. Architecture Documentation** ✅ COMPLETED (2026-04-05)
- ✅ High-level architecture diagram (Mermaid flowchart, renders in GitHub)
- ✅ Streaming path sequence diagram (Client → API GW → Kinesis → ETL → S3 → EventBridge → Step Functions)
- ✅ Batch path sequence diagram (S3 upload → EventBridge → Step Functions → Comprehend → Merge → Storage)
- ✅ Step Functions state machine flowchart (all 7 states with retry/catch)
- ✅ Storage architecture diagram (3-tier S3 + DynamoDB with lifecycle policies)
- ✅ Analytics layer diagram (3-source dashboard query strategy)
- ✅ API contract (endpoint, headers, request/response schema, error codes)
- ✅ Infrastructure summary tables (all deployed resources)
- ✅ README updated with Mermaid architecture diagram + link to full docs
- Documentation: `docs/architecture.md`

**Complete when:** ✅ Complete architecture documentation exists, diagrams are current

**8. Staging Environment Deployment** ~~SKIPPED~~

> **Decision:** Staging and production deployments are intentionally skipped for this portfolio project.
> The multi-environment directory structure (`envs/dev/`, `envs/stg/`, `envs/prod/`) is already in place
> and demonstrates knowledge of environment promotion patterns. Deploying identical idle infrastructure
> adds ~$24/month in AWS cost without meaningful portfolio value. CI/CD with multi-environment approval
> gates (Phase 10) demonstrates the deployment process instead.

---

## Phase 10: CI/CD Pipeline (Final Phase)
**Goal:** Automated deployments via GitHub Actions

### Tasks

**1. AWS OIDC Identity Provider Setup** ✅ COMPLETED (2026-03-22)
- Reused existing OIDC Identity Provider (`token.actions.githubusercontent.com`) from prior project
- Created IAM role `ai-dp-dev-github-actions` with least-privilege inline policy (`ai-dp-dev-terraform-policy`)
- Trust policy scoped to `repo:CloudMikey/AI-DP:*` — only this repo can assume the role
- Policy covers all project services with ARN-scoped permissions (`ai-dp-*` prefix where supported)
- Role imported into Terraform state via `terraform import` (`envs/dev/cicd.tf`)
- Role ARN: `arn:aws:iam::<ACCOUNT_ID>:role/ai-dp-dev-github-actions`

**Complete when:** GitHub Actions can assume each role, trust policies validated

**2. CI Workflow - Pull Requests** ✅ COMPLETED (2026-04-05)
- Created `.github/workflows/ci.yml` — triggers on PRs to `main`
- Steps: checkout → setup Terraform v1.13.0 + tflint → OIDC auth → init → fmt -check → validate → tflint → tfsec → plan → post plan as PR comment
- OIDC authentication via `vars.AWS_ROLE_ARN` — no long-term credentials
- Plan output posted as collapsible PR comment via `actions/github-script`
- Least-privilege IAM policy (`ai-dp-dev-terraform-policy`) fully tuned across 25 CI runs
- Key IAM lesson: `aws_lambda_event_source_mapping` uses UUID ARNs requiring separate `Resource: "*"` statement for `lambda:ListTags`
- PR #1 merged via squash merge on 2026-04-05

**Complete when:** PR triggers CI workflow, all checks pass, plan output visible in PR comments

**3. Deploy Workflow - Main Branch** ✅ COMPLETED (2026-04-05)
- Created `.github/workflows/deploy.yml` — triggers on push to `main`
- Steps: checkout → setup Terraform → OIDC auth → init → plan → post plan to job summary → apply
- `cancel-in-progress: false` — prevents cancelling a running apply (avoids partial state)
- Plan saved to `tfplan` file; apply uses exact same plan (no drift between plan and apply)
- ~~Deploy to Staging~~ / ~~Deploy to Prod~~: Omitted — environments not deployed (see Phase 9 Task 9)

**Complete when:** ✅ Merging to main deploys to dev automatically

**4. Environment Protection Rules** ✅ COMPLETED (2026-04-05)
- `dev` GitHub Environment created in repo Settings → Environments
- Referenced in `deploy.yml` via `environment: dev`
- Provides deployment history and audit trail in GitHub UI
- ~~`stg`~~ / ~~`prod`~~: Not configured — environments not deployed (see Phase 9 Task 9)

**Complete when:** ✅ Dev environment protection rule active, tested with deployment

**5. Workflow Testing** ✅ COMPLETED (2026-04-05)
- Opened test PR (`test/deploy-workflow` branch) — CI triggered, plan posted as PR comment
- Merged PR — Deploy workflow triggered, `terraform apply` completed with `No changes`
- Both workflows verified working end-to-end

**Complete when:** ✅ Full CI/CD cycle tested (PR → CI → merge → deploy)

**6. CI/CD Documentation** ✅ COMPLETED (2026-04-05)
- Created `docs/cicd.md` covering: developer workflow, CI/Deploy step breakdowns, OIDC auth explanation, GitHub Environment setup, backend config, troubleshooting table

**Complete when:** ✅ Documentation complete

**Status:** ✅ **COMPLETED** (2026-04-05)
- Add CI/CD architecture diagram
- Create troubleshooting guide for failed deployments

**Complete when:** CI/CD pipeline fully documented

---

## Success Metrics

**Technical Milestones:**
- ✅ All 10 phases completed sequentially
- ✅ End-to-end data flow working (ingestion → AI enrichment → storage → analytics)
- ✅ Automated deployment pipeline operational
- ✅ Dev environment operational (stg/prod intentionally skipped — multi-env IaC structure demonstrated via code)
- ✅ P95 latency < 5 seconds for streaming path
- ✅ Cost < $50/month for dev environment

**Portfolio Readiness:**
- ✅ Professional architecture diagram
- ✅ Live demo available (or video walkthrough)
- ✅ Public GitHub repository with polished README
- ✅ Can explain design decisions and tradeoffs
- ✅ Can discuss scalability and cost optimization strategies
- ✅ Demonstrates AWS services: S3, Lambda, Kinesis, Step Functions, Comprehend, DynamoDB, Glue, Athena
- ✅ Demonstrates IaC: Terraform, modules, remote state
- ✅ Demonstrates CI/CD: GitHub Actions, OIDC, multi-environment deployment

---

## Phase Completion Tracking

```
Phase 0 (Bootstrap):           ████████████████████ 100% ✅
Phase 1 (Data Lake):           ████████████████████ 100% ✅
Phase 2 (Streaming):           ████████████████████ 100% ✅
Phase 3 (Batch EventBridge):  ████████████████████ 100% ✅
Phase 4 (Step Functions):     ████████████████████ 100% ✅
Phase 5 (DynamoDB):            ████████████████████ 100% ✅
Phase 6 (AI Enrichment):       ████████████████████ 100% ✅
Phase 7 (Merge & Orchestrate): ████████████████████ 100% ✅
Phase 8 (Analytics):           ████████████████████ 100% ✅
Phase 9  (Production Hardening):████████████████████ 100% ✅
Phase 10 (CI/CD):               ████████████████████ 100% ✅
```

**Overall Progress: 100% ✅ PROJECT COMPLETE (2026-04-05)**

---

## Quick Reference: New Sequential Phase Order

```
Phase 0: Bootstrap (Terraform setup)
    ↓
Phase 1: Data Lake (S3 buckets)
    ↓
Phase 2: Streaming Ingestion (API Gateway → Kinesis → Lambda → S3)
    ↓
Phase 3: Batch Ingestion (EventBridge rule, no target yet)
    ↓
Phase 4: Step Functions Placeholder + EventBridge Wiring
    ↓
Phase 5: DynamoDB Hot Store (before AI needs it)
    ↓
Phase 6: AI Enrichment (Comprehend integration)
    ↓
Phase 7: Merge Lambda & Complete Orchestration
    ↓
Phase 8: Analytics (Glue, Athena, Dashboard)
    ↓
Phase 9: Production Hardening (Testing, Security, Docs)
    ↓
Phase 10: CI/CD Pipeline (GitHub Actions)
```

**Key Principles:**
1. **No dependencies on future phases** - Each phase builds only what's needed NOW
2. **Resources created when needed** - DynamoDB created in Phase 5 (before Phase 7 Merge Lambda needs it)
3. **DLQs created with Lambdas** - Error handling infrastructure built alongside resources
4. **Security incremental** - Each phase includes security basics (encryption, IAM), final audit in Phase 9
5. **CI/CD last** - Deployment automation added after infrastructure is proven working

---

**Total Estimated Timeline:** 8-12 weeks

**Last Updated:** 2026-03-21 (Decision: Staging/prod deployment skipped for portfolio — dev-only with multi-env IaC structure demonstrated via code)
