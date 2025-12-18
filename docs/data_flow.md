# AI-DP Data Flow Overview

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          DATA INGESTION LAYER                           │
├─────────────────────────────────┬───────────────────────────────────────┤
│     STREAMING PATH              │         BATCH PATH                    │
│                                 │                                       │
│  ① HTTP POST Request            │  ① S3 Batch Upload                   │
│     ↓                           │     ↓                                 │
│  ② API Gateway                  │  ② EventBridge Rule                  │
│     ↓                           │     (triggers on raw/ uploads)        │
│  ③ Kinesis Data Stream          │                                       │
│     ↓                           │                                       │
│  ④ ETL Lambda ─────────────────────→ ③ S3 raw/ (date-partitioned)      │
│     (validate, normalize)       │                                       │
└─────────────────────────────────┴───────────────────────────────────────┘
                                         ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                      ORCHESTRATION & AI ENRICHMENT                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ④ EventBridge → Step Functions State Machine                          │
│     (ai-dp-dev-orchestrator)                                            │
│                                                                         │
│     ┌─────────────────────────────────────────────────────┐            │
│     │          Parallel AI Enrichment Tasks               │            │
│     │                                                      │            │
│     │  ┌──────────────────────┐  ┌──────────────────────┐ │            │
│     │  │ AWS Comprehend       │  │ AWS Comprehend       │ │            │
│     │  │ DetectSentiment      │  │ DetectEntities       │ │            │
│     │  │                      │  │                      │ │            │
│     │  │ Returns:             │  │ Returns:             │ │            │
│     │  │ - Sentiment score    │  │ - Organizations      │ │            │
│     │  │ - Confidence %       │  │ - People             │ │            │
│     │  │ - Classification     │  │ - Locations          │ │            │
│     │  └──────────────────────┘  └──────────────────────┘ │            │
│     │              ↓                       ↓               │            │
│     └──────────────┴───────────────────────┴───────────────┘            │
│                            ↓                                            │
│                    ⑤ Merge Lambda                                       │
│                    (combines AI results)                                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        DUAL STORAGE STRATEGY                            │
├────────────────────────────────────┬────────────────────────────────────┤
│         HOT STORE (DynamoDB)       │      COLD STORE (S3)               │
│                                    │                                    │
│  ⑥ ai-dp-dev-enriched-data        │  ⑥ s3://ai-dp-data-lake-dev/      │
│                                    │     processed/                     │
│  Schema:                           │                                    │
│  - recordId (PK)                   │  Partitioned by date:              │
│  - timestamp (SK)                  │  - year=YYYY/                      │
│  - recordType                      │  - month=MM/                       │
│  - content                         │  - day=DD/                         │
│  - sentiment                       │                                    │
│  - entities                        │  Lifecycle:                        │
│  - expiresAt (TTL: 30 days)        │  - 60d → Intelligent-Tiering       │
│                                    │  - 120d → Glacier                  │
│  GSI: timestamp-index              │  - 365d → Expiration               │
│  - Query by recordType + time      │                                    │
│                                    │                                    │
│  Use Case:                         │  Use Case:                         │
│  - Real-time dashboard queries     │  - Historical analytics (Athena)   │
│  - Last 30 days of data            │  - Long-term data retention        │
│  - Low-latency reads               │  - Cost-effective storage          │
│                                    │                                    │
└────────────────────────────────────┴────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    ANALYTICS LAYER (Phase 8 - Complete)                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ⑦ AWS Glue Crawler (ai-dp-dev-crawler)                                │
│     - Catalogs processed/ S3 data (on-demand)                           │
│     - Creates table: ai-dp-dev-analytics.processed                      │
│     - Auto-detects partitions: year/month/day                           │
│     - Schema policy: UPDATE_IN_DATABASE (handles evolving fields)       │
│                                                                         │
│  ⑧ Amazon Athena (ai-dp-dev-workgroup)                                 │
│     - SQL queries on S3 data lake                                       │
│     - Results bucket: ai-dp-athena-results-dev-us-west-2 (7d lifecycle) │
│     - Partition pruning: Only scans relevant year/month/day folders     │
│                                                                         │
│  ⑨ Visualization Dashboard (dashboard/index.html)                      │
│     ┌─────────────────────┬──────────────────────┐                     │
│     │ Real-time Metrics   │ Historical Analytics │                     │
│     │ (DynamoDB)          │ (Athena/S3)          │                     │
│     │ - Last 20 records   │ - Sentiment pie chart│                     │
│     │ - Events table      │ - SQL aggregations   │                     │
│     │ - Recent sentiment  │ - Trend analysis     │                     │
│     └─────────────────────┴──────────────────────┘                     │
│     Tech: HTML/CSS/JS + Chart.js + AWS SDK v3                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Detailed Data Flow Walkthrough

### Path 1: Streaming Ingestion (Real-time Events)

```
User Application
    │
    │ HTTP POST /ingest
    │ {
    │   "recordId": "rec-123",
    │   "recordType": "text",
    │   "content": "This is a sample message"
    │ }
    ↓
API Gateway (57cnx9jpje.execute-api.us-west-1.amazonaws.com)
    │
    │ Direct Integration (no Lambda)
    ↓
Kinesis Data Stream (ai-dp-dev-ingestion-stream)
    │
    │ Event Source Mapping
    │ - Batch: 100 records
    │ - Retry: 3 attempts
    ↓
ETL Lambda (ai-dp-dev-etl)
    │
    │ Processing:
    │ 1. Validate JSON (recordId, recordType, content required)
    │ 2. Normalize data (add processed_at, lambda_version)
    │ 3. Date partition calculation (year, month, day)
    │
    │ Output:
    │ {
    │   "recordId": "rec-123",
    │   "recordType": "text",
    │   "content": "This is a sample message",
    │   "processed_at": "2025-12-13T10:30:00Z",
    │   "lambda_version": "$LATEST",
    │   "lambda_name": "ai-dp-dev-etl"
    │ }
    ↓
S3 raw/ (ai-dp-data-lake-dev-us-west-1)
    │
    │ Path: raw/year=2025/month=12/day=13/rec-123.json
    │ Triggers S3 Event Notification
    ↓
[CONTINUES TO ORCHESTRATION LAYER BELOW]
```

### Path 2: Batch Ingestion (File Uploads)

```
Data Engineer/Automated Process
    │
    │ AWS CLI / SDK / Console Upload
    │ aws s3 cp data.json s3://ai-dp-data-lake-dev-us-west-1/raw/
    ↓
S3 raw/ (ai-dp-data-lake-dev-us-west-1)
    │
    │ S3 Event: ObjectCreated
    │ Bucket: ai-dp-data-lake-dev-us-west-1
    │ Key: raw/year=2025/month=12/day=13/data.json
    ↓
EventBridge (S3 Event Notifications enabled)
    │
    │ Event Pattern Match:
    │ - source: aws.s3
    │ - detail-type: Object Created
    │ - bucket: ai-dp-data-lake-dev-us-west-1
    │ - key prefix: raw/
    ↓
EventBridge Rule (ai-dp-dev-s3-batch-ingestion)
    │
    │ Target: Step Functions
    ↓
[CONTINUES TO ORCHESTRATION LAYER BELOW]
```

### Orchestration & AI Enrichment (Both Paths Converge)

```
Step Functions State Machine (ai-dp-dev-orchestrator)
    │
    │ Input:
    │ {
    │   "bucket": "ai-dp-data-lake-dev-us-west-1",
    │   "key": "raw/year=2025/month=12/day=13/rec-123.json"
    │ }
    ↓
ReadS3Object State
    │
    │ AWS SDK Integration: s3:GetObject
    │ Reads file content from S3
    ↓
ParallelEnrichment State
    │
    ├─────────────────────────────┬─────────────────────────────┐
    │                             │                             │
    ↓                             ↓                             ↓
DetectSentiment               DetectEntities              (Future: Rekognition)
(AWS Comprehend)              (AWS Comprehend)
    │                             │
    │ Input: text content         │ Input: text content
    │                             │
    │ Output:                     │ Output:
    │ {                           │ {
    │   "Sentiment": "POSITIVE",  │   "Entities": [
    │   "SentimentScore": {       │     {
    │     "Positive": 0.9876,     │       "Text": "AWS",
    │     "Negative": 0.0001,     │       "Type": "ORGANIZATION",
    │     "Neutral": 0.0120,      │       "Score": 0.99
    │     "Mixed": 0.0003         │     }
    │   }                         │   ]
    │ }                           │ }
    │                             │
    └─────────────────────────────┴─────────────────────────────┘
                                  ↓
                        Results Combined by Step Functions
                                  ↓
                        InvokeMergeLambda State
                                  │
                                  │ Input: original record + AI results
                                  ↓
                        Merge Lambda (ai-dp-dev-merge)
                                  │
                                  │ Processing:
                                  │ 1. Combine original + sentiment + entities
                                  │ 2. Calculate expiresAt (now + 30 days)
                                  │ 3. Prepare dual writes
                                  │
                                  │ Output:
                                  │ {
                                  │   "recordId": "rec-123",
                                  │   "timestamp": 1702468200,
                                  │   "recordType": "text",
                                  │   "content": "This is a sample message",
                                  │   "sentiment": "POSITIVE",
                                  │   "sentimentScores": {...},
                                  │   "entities": [...],
                                  │   "processed_at": "2025-12-13T10:30:00Z",
                                  │   "expiresAt": 1705060200
                                  │ }
                                  ↓
                    ┌─────────────┴──────────────┐
                    ↓                            ↓
            DynamoDB PutItem              S3 PutObject
            (Hot Store)                   (Cold Store)
                    │                            │
                    │                            │
                    ↓                            ↓
    ai-dp-dev-enriched-data          processed/year=2025/month=12/day=13/
                                     rec-123-enriched.json
```

---

## Data Retention & Lifecycle

### S3 Data Lake Lifecycle

```
raw/ Layer:
Day 0  ──────────────────> Day 30 ──────────> Day 90 ──────────> Day 180
  │                          │                  │                   │
Created                 Intelligent-         Glacier           Deleted
(Standard)               Tiering


processed/ Layer:
Day 0  ──────────────────> Day 60 ──────────> Day 120 ─────────> Day 365
  │                          │                  │                   │
Created                 Intelligent-         Glacier           Deleted
(Standard)               Tiering


curated/ Layer:
Day 0  ───────────────────────────────────────────────────────> ∞
  │                                                              │
Created                                                    Permanent
(Standard)                                                (No expiration)
```

### DynamoDB Hot Store Lifecycle

```
Record Created
    │
    │ expiresAt = current_timestamp + 30 days
    ↓
DynamoDB Table (ai-dp-dev-enriched-data)
    │
    │ TTL Enabled (checks every hour)
    ↓
Day 30: Automatic Deletion
    │
    │ Record removed from DynamoDB
    │ Historical data still in S3 processed/
    ↓
Query S3 via Athena for records older than 30 days
```

---

## Error Handling & Recovery

### ETL Lambda Error Flow

```
Kinesis Event → ETL Lambda
                     │
                     │ Validation fails OR processing error
                     ↓
                Auto-retry (3 attempts)
                     │
                     │ Still failing after 3 retries
                     ↓
           SQS DLQ (ai-dp-dev-etl-dlq)
                     │
                     │ Retention: 14 days
                     ↓
           CloudWatch Alarm triggers
                     │
                     ↓
           Engineer investigates
                     │
                     ↓
           Fix issue, replay via DLQ
```

### Merge Lambda Error Flow

```
Step Functions → Merge Lambda
                     │
                     │ S3/DynamoDB write fails
                     ↓
           Step Functions Catch Block
                     │
                     │ Retries with exponential backoff
                     ↓
                Still failing?
                     │
                     ├─→ Success: Continue to End state
                     │
                     └─→ Failure: Send to DLQ (ai-dp-dev-merge-dlq)
                              │
                              ↓
                        CloudWatch Alarm
                              │
                              ↓
                        Manual replay
```

---

## Query Patterns

### Real-time Queries (DynamoDB)

```sql
-- Get specific record
recordId = "rec-123" AND timestamp = 1702468200

-- Get all text records from last 7 days (using GSI)
recordType = "text" AND timestamp > (now - 7 days)

-- Get latest records (scan with limit)
SCAN LIMIT 100 ORDER BY timestamp DESC
```

### Historical Queries (Athena on S3)

```sql
-- Count sentiment distribution for December 2025
SELECT sentiment, COUNT(*) as count
FROM processed_data
WHERE year = '2025' AND month = '12'
GROUP BY sentiment;

-- Top entities mentioned in Q4 2025
SELECT entity_text, entity_type, COUNT(*) as mentions
FROM processed_data
CROSS JOIN UNNEST(entities) AS t(entity)
WHERE year = '2025' AND month IN ('10', '11', '12')
GROUP BY entity_text, entity_type
ORDER BY mentions DESC
LIMIT 20;

-- Date-partitioned query (efficient)
SELECT *
FROM processed_data
WHERE year = '2025' AND month = '12' AND day = '13';
```

---

## Summary: Why This Architecture?

| Component | Purpose | Why Chosen |
|-----------|---------|------------|
| **Kinesis** | Streaming ingestion | Real-time, auto-scales, native Lambda integration |
| **S3 3-layer** | Data lake storage | Cost-effective, lifecycle policies, Athena-ready |
| **Step Functions** | Orchestration | Visual workflow, parallel execution, managed retries |
| **Comprehend** | AI enrichment | Serverless, no model training, pay-per-use |
| **DynamoDB** | Hot store | Low-latency queries, TTL for auto-cleanup |
| **Date partitioning** | S3 optimization | Athena skips irrelevant data, faster queries |
| **DLQs** | Error handling | Failed records preserved for replay |
| **Dual storage** | Cost vs. speed | DynamoDB (fast, expensive) + S3 (slow, cheap) |

---

## Analytics Query Patterns (Phase 8 Complete)

### Athena SQL Examples

**Sentiment distribution (aggregated):**
```sql
SELECT sentiment, COUNT(*) as count
FROM "ai-dp-dev-analytics"."processed"
GROUP BY sentiment;
```

**Time-based partitioned query (cost-optimized):**
```sql
SELECT *
FROM "ai-dp-dev-analytics"."processed"
WHERE year = '2025' AND month = '12' AND day = '16';
```

**Entity extraction analysis:**
```sql
SELECT recordId, sentiment, entities
FROM "ai-dp-dev-analytics"."processed"
WHERE sentiment = 'POSITIVE'
LIMIT 10;
```

### Dashboard Data Sources

**DynamoDB (Real-time):**
- Last 20 records (ScanCommand with Limit)
- Recent events table with timestamp/sentiment/type

**Athena (Historical):**
- Sentiment distribution pie chart (GROUP BY sentiment)
- Long-term trend analysis across date partitions

---

## Next Phase: Production Hardening (Phase 9)

**Upcoming additions:**
- CloudWatch alarms for all critical components
- API Gateway throttling and rate limiting
- Auto-scaling configurations
- Comprehensive error monitoring
