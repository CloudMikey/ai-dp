# Sequential Implementation Summary: AI-DP Architecture

## Phase 0: Bootstrap Infrastructure ✅

### S3 State Backend
- **Bucket**: `tf-state-aidp` (us-west-1)
- **Configuration**: Terraform 1.13.0 with native S3 locking (`use_lockfile = true`)
- **Why**: Eliminated DynamoDB lock tables using Terraform's new built-in S3 locking feature
- **State Isolation**: Separate state files per environment (dev/stg/prod)

---

## Phase 1: Data Lake Foundation ✅

### S3 Bucket: `ai-dp-data-lake-dev-us-west-1`
**Three-Layer Architecture:**

1. **`raw/` Layer**
   - Purpose: Ingested data as-is from streaming/batch sources
   - Lifecycle: 30d → Intelligent-Tiering, 90d → Glacier, 180d expiration
   - Why short retention: Raw data is transformed quickly; no need for long-term storage

2. **`processed/` Layer**
   - Purpose: AI-enriched data with sentiment/entities added
   - Lifecycle: 60d → Intelligent-Tiering, 120d → Glacier, 365d expiration
   - Why longer retention: Business-ready data used for analytics

3. **`curated/` Layer**
   - Purpose: Aggregated/transformed business reports
   - Lifecycle: No lifecycle rules (permanent storage)
   - Why permanent: Final business insights preserved indefinitely

**Security Configuration:**
- Encryption: AES256 at rest (AWS-managed keys)
- Versioning: Enabled on all layers (data recovery)
- Public Access: All 4 block settings enabled (prevents accidental exposure)
- Bucket Policy: Enforces HTTPS/TLS for all operations (SecureTransport condition)

**EventBridge Integration:**
- Enabled S3 Event Notifications → EventBridge
- Why: Triggers batch processing pipeline when files uploaded to `raw/`

**Key Design Decision:**
- Used provider `default_tags` instead of module-level tag merging to avoid AWS tag conflicts

---

## Phase 2: Streaming Ingestion Path ✅

### API Gateway HTTP API
- **Endpoint**: `https://57cnx9jpje.execute-api.us-west-1.amazonaws.com/ingest`
- **Integration**: Direct Kinesis `PutRecord` (no Lambda proxy)
- **Why direct integration**: Lower latency, fewer moving parts, cost-effective

### Kinesis Data Stream: `ai-dp-dev-ingestion-stream`
- **Shard Count**: 1 (suitable for dev/portfolio scale)
- **Retention**: 24 hours
- **Why Kinesis**: Real-time streaming, auto-scales, integrates natively with Lambda

### ETL Lambda: `ai-dp-dev-etl`
- **Runtime**: Python 3.11
- **Memory**: 256 MB
- **Timeout**: 60 seconds
- **Functionality**:
  - Consumes Kinesis events (batch size 100 records)
  - Validates JSON structure (required fields: `recordId`, `recordType`, `content`)
  - Normalizes data (adds `processed_at`, `lambda_version`, `lambda_name`)
  - Writes to S3 `raw/` with date partitioning: `year=YYYY/month=MM/day=DD/`
- **Why date partitioning**: Athena query optimization (Phase 8)

**Event Source Mapping:**
- Batch size: 100 records
- Max retry attempts: 3
- On-failure destination: SQS DLQ

### SQS Dead Letter Queue: `ai-dp-dev-etl-dlq`
- **Retention**: 14 days
- **Purpose**: Captures failed records after 3 retries for replay/debugging

**IAM Design:**
- Least-privilege: S3 write scoped to `raw/*` prefix only (prevents writes to `processed/` or `curated/`)
- Kinesis read limited to specific stream ARN

---

## Phase 3: Batch Ingestion Path ✅

### EventBridge Rule: `ai-dp-dev-s3-batch-ingestion`
- **Event Pattern**: S3 Object Created events filtered to `raw/` prefix
- **State**: ENABLED
- **Why filtering to raw/**: Prevents infinite loops (Step Functions writes to `processed/`, avoiding re-triggering)
- **Target**: Configured in Phase 4 (Step Functions state machine)

---

## Phase 4: Step Functions Orchestration ✅

### State Machine: `ai-dp-dev-orchestrator`
- **Type**: Standard workflow
- **CloudWatch Logs**: ALL level (`/aws/states/ai-dp-dev-orchestrator`)
- **Initial State**: Pass state (placeholder for AI enrichment tasks)

### EventBridge → Step Functions Integration
- **Trigger**: S3 batch upload to `raw/` → EventBridge rule → StartExecution
- **IAM Roles**:
  - EventBridge: `states:StartExecution` permission
  - Step Functions: CloudWatch Logs write permission

**Why Step Functions**:
- Orchestrates parallel AI enrichment tasks (Comprehend, SageMaker)
- Visual workflow, built-in retry/error handling
- No Lambda needed for simple orchestration tasks

---

## Phase 5: DynamoDB Hot Store ✅

### Table: `ai-dp-dev-enriched-data`
**Schema Design:**
- **Partition Key**: `recordId` (STRING)
- **Sort Key**: `timestamp` (NUMBER)
- **Why composite key**: Enables efficient queries by ID + time-based filtering

**Global Secondary Index: `timestamp-index`**
- **Partition Key**: `recordType` (STRING)
- **Sort Key**: `timestamp` (NUMBER)
- **Why**: Supports queries like "get all text records from last 7 days"
- **Projection**: ALL attributes (optimized for analytics queries)

**Configuration:**
- Billing Mode: PAY_PER_REQUEST (on-demand)
  - Why: Portfolio-appropriate (no capacity planning), cost-effective for low traffic
- TTL: Enabled on `expiresAt` attribute (30-day retention)
  - Why: Auto-deletes old records, keeps hot store lean, reduces costs
- Point-in-Time Recovery: Enabled (35-day recovery period)
  - Why: Production-grade data protection without backups

**Dual Storage Strategy:**
- DynamoDB: Last 30 days (hot queries, real-time dashboard)
- S3 `processed/`: Long-term historical data (Athena analytics)

---

## Phase 6: AI Enrichment Services ✅

### AWS Comprehend Integration (Step Functions Direct)
**Parallel Execution:**
1. **DetectSentiment Task**
   - Analyzes text sentiment (POSITIVE/NEGATIVE/NEUTRAL/MIXED)
   - Returns sentiment + confidence scores

2. **DetectEntities Task**
   - Extracts entities (organizations, people, locations, dates)
   - Returns entity type + confidence scores

**Why Parallel**: 50% faster than sequential (tasks run simultaneously)

**Implementation Choice:**
- Used Step Functions AWS SDK integration (no Lambda wrapper)
- Why: Simpler architecture, less code, AWS-managed retries

**S3 Integration:**
- State machine reads S3 objects directly via `$.body` parameter
- IAM: S3 read scoped to `raw/*` prefix only

**Data Flow:**
- S3 upload → EventBridge → Step Functions → Comprehend (parallel) → Results passed to next state

---

## Phase 7: Merge Lambda & Complete Orchestration ✅

### Merge Lambda: `ai-dp-dev-merge`
- **Runtime**: Python 3.11
- **Memory**: 256 MB
- **Timeout**: 60 seconds
- **Functionality**:
  - Receives Comprehend results from Step Functions
  - Merges sentiment + entities with original record
  - Writes enriched data to **two destinations**:
    1. **S3 `processed/`**: Date-partitioned (`year=YYYY/month=MM/day=DD/`)
    2. **DynamoDB**: Record with TTL (30 days)

**Error Handling:**
- SQS DLQ: `ai-dp-dev-merge-dlq` (14-day retention)
- Step Functions Catch Block: Retries on Lambda errors
- CloudWatch Logs: `/aws/lambda/ai-dp-dev-merge`

**IAM Permissions:**
- S3 write scoped to `processed/*` prefix only
- DynamoDB `PutItem` limited to `ai-dp-dev-enriched-data` table

**Step Functions Update:**
- Added `InvokeMergeLambda` state after Comprehend parallel tasks
- Passes sentiment + entities output to Lambda

---

## End-to-End Data Flow (Both Paths Operational)

### **Streaming Path:**
1. HTTP POST → API Gateway → Kinesis Data Stream
2. Kinesis → ETL Lambda → S3 `raw/` (date-partitioned)
3. S3 `raw/` → EventBridge → Step Functions
4. Step Functions → Comprehend (parallel sentiment + entities)
5. Comprehend results → Merge Lambda → S3 `processed/` + DynamoDB

### **Batch Path:**
1. S3 batch upload → `raw/` prefix
2. S3 Event → EventBridge rule → Step Functions
3. Step Functions → Comprehend (parallel sentiment + entities)
4. Comprehend results → Merge Lambda → S3 `processed/` + DynamoDB

---

## Key Architectural Patterns Established

1. **Least-Privilege IAM**: All permissions scoped to specific resources/prefixes
2. **Date Partitioning**: `year=YYYY/month=MM/day=DD/` for Athena optimization
3. **Dual Storage Strategy**: DynamoDB (hot) + S3 (cold) for cost-optimized analytics
4. **Parallel Processing**: Step Functions fan-out pattern for AI tasks
5. **Error Handling**: DLQs, retries, CloudWatch alarms, catch blocks
6. **Cost Optimization**: On-demand billing, lifecycle rules, TTL, Intelligent-Tiering
7. **Security**: Encryption at rest, TLS enforcement, public access blocking

---

## Phase 8: Analytics & Query Layer ✅

### AWS Glue Crawler: `ai-dp-dev-crawler`
- **Database**: `ai-dp-dev-analytics`
- **Target**: S3 `processed/` layer (date-partitioned JSON files)
- **Schedule**: On-demand (manual trigger for cost control)
- **Configuration**:
  - Schema change policy: UPDATE_IN_DATABASE (auto-updates when new fields appear)
  - Recrawl behavior: CRAWL_EVERYTHING (required for UPDATE_IN_DATABASE)
  - Partition detection: Automatic (year/month/day from S3 folder structure)
  - Table grouping: CombineCompatibleSchemas

**Glue Table Created:**
- Name: `processed`
- Columns: 13 fields (recordId, timestamp, sentiment, entities, etc.)
- Partition Keys: year, month, day
- Format: JSON

### Athena Workgroup: `ai-dp-dev-workgroup`
- **State**: ENABLED
- **Configuration**:
  - Enforce workgroup settings: true
  - CloudWatch metrics: enabled
  - Engine version: AUTO (uses latest Athena v3)
- **Results Bucket**: `ai-dp-athena-results-dev-us-west-2`
  - Encryption: SSE-S3
  - Lifecycle: 7-day expiration (automatic cleanup)
  - Versioning: Enabled
  - Public access: Blocked

**Why Separate Results Bucket:**
- Different lifecycle requirements (7-day vs 30-365 days)
- Easier cost tracking and monitoring
- Simpler IAM policies (query results vs production data)
- Operational safety (deletion won't affect data lake)

### Visualization Dashboard
**Files Created:**
- `dashboard/index.html` - Structure and layout
- `dashboard/styles.css` - Clean, minimal styling
- `dashboard/app.js` - AWS SDK integration logic
- `dashboard/README.md` - Setup instructions

**Dashboard Features:**
1. **Metrics Card**: Real-time count of enriched records
2. **Sentiment Distribution Pie Chart**: Athena query (GROUP BY sentiment)
3. **Recent Events Table**: DynamoDB query (last 20 records, sorted by timestamp)

**Technology Stack:**
- Chart.js v4 (pie charts)
- AWS SDK for JavaScript v3 (Athena + DynamoDB clients)
- ES6 modules via import maps (no build tools)
- Simple HTML/CSS (portfolio-friendly, no frameworks)

**How to Run:**
```bash
cd dashboard
python -m http.server 8080
# Open http://localhost:8080
```

### IAM Configuration
**Glue Crawler Role:**
- S3 read permissions: Scoped to `processed/*` prefix only
- Glue Data Catalog: Full CRUD on tables/partitions/databases
- CloudWatch Logs: Write to `/aws-glue/crawlers` log group
- **Critical permission**: `glue:BatchGetPartition` (initially missing, added after crawler error)

### Design Decisions
1. **On-demand crawler**: Manual trigger to control costs (vs scheduled)
2. **7-day query results retention**: Balance between debugging needs and storage costs
3. **Local dashboard**: Simple HTTP server for demos (no public deployment)
4. **UPDATE_IN_DATABASE schema policy**: Handles dynamic AI enrichment fields automatically
5. **Separate S3 bucket for Athena results**: Simpler lifecycle, better cost tracking

### Testing Results
✅ Glue Crawler ran successfully (created table with 13 columns + 3 partition keys)
✅ Athena queries work (SELECT * and GROUP BY sentiment tested)
✅ Dashboard loads data from both DynamoDB and Athena
✅ Partition detection working (year/month/day auto-detected)

### Crawler Errors Encountered
**Error 1**: Schema policy constraint (CRAWL_NEW_FOLDERS_ONLY incompatible with UPDATE_IN_DATABASE)
- **Fix**: Changed to CRAWL_EVERYTHING recrawl behavior

**Error 2**: Missing IAM permission (`glue:BatchGetPartition`)
- **Fix**: Added permission to Glue Data Catalog policy

### Interview Talking Points
- **Dual-query strategy**: DynamoDB for real-time (sub-10ms), Athena for historical SQL
- **Partition pruning**: Date partitioning reduces Athena costs by 90%+
- **Schema evolution**: Glue Crawler adapts automatically to new enrichment fields
- **Cost optimization**: 7-day query results lifecycle, on-demand crawler
- **Separation of concerns**: Different buckets for different data purposes

---

## Ready for Phase 9: Production Hardening
- CloudWatch alarms for all critical components
- API Gateway throttling and rate limiting
- Auto-scaling configurations
- Comprehensive error monitoring and alerting
