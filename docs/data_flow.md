# Data Flow — AI-Powered Serverless Data Pipeline

End-to-end walkthrough of how data moves through the pipeline, from ingestion to analytics.

---

## Two Ingestion Paths, One Enrichment Pipeline

The pipeline accepts data through two entry points that converge at EventBridge:

```
REST API → Kinesis → ETL Lambda → S3 raw/  ──┐
                                               ├──► EventBridge → Step Functions → ...
Direct S3 Upload ──────────────────────────────┘
```

EventBridge is the convergence point. Both paths write to `S3 raw/` and both trigger the same enrichment pipeline.

---

## Path 1: Streaming Ingestion (API Gateway → Kinesis)

### Step 1 — API Gateway receives the request

```
POST https://<api-id>.execute-api.us-west-2.amazonaws.com/ingest
Content-Type: application/json
X-Partition-Key: user-123

{
  "event_type": "page_view",
  "event_timestamp": "2026-01-25T12:00:00Z",
  "user_id": "user-123",
  "page": "/dashboard"
}
```

API Gateway uses a direct AWS service integration (no Lambda proxy). It calls `kinesis:PutRecord` directly, using the `X-Partition-Key` header as the Kinesis partition key. Response time: ~50ms.

**Response:**
```json
{"SequenceNumber": "49670192848271239842602659163669398716174920392225325058", "ShardId": "shardId-000000000000"}
```

### Step 2 — ETL Lambda processes the Kinesis batch

The Lambda polls the stream and receives up to 100 records per invocation. For each record:

1. Base64-decode the Kinesis data payload
2. Validate required fields: `event_type` (string), `event_timestamp` (ISO 8601)
3. Normalize timestamp to UTC
4. Add pipeline metadata: `ingestion_source`, `pipeline_version`, `processed_at`
5. Write to S3

**S3 key pattern:** `raw/year=YYYY/month=MM/day=DD/{sequenceNumber}.json`

The Kinesis sequence number is used as the filename. This ensures idempotent writes — if the Lambda retries a failed record, it overwrites the same S3 object instead of creating a duplicate. See `docs/errorlog.md` Pattern #4 for details.

**Failed records** are sent to the SQS DLQ (`ai-dp-dev-etl-dlq`) after 3 retry attempts. DLQ messages can be manually replayed by re-sending to Kinesis or re-uploading to S3.

---

## Path 2: Batch Ingestion (Direct S3 Upload)

```bash
aws s3 cp events.json s3://ai-dp-data-lake-dev-us-west-2/raw/2026/01/25/batch-001.json
```

Any file uploaded to the `raw/` prefix triggers EventBridge. The enrichment pipeline treats batch files identically to streaming records — same Step Functions execution, same Comprehend calls, same Merge Lambda output.

---

## Enrichment Pipeline (Both Paths)

### Step 3 — EventBridge triggers Step Functions

An EventBridge rule filters for `s3:ObjectCreated:*` events on the `raw/` prefix. On match, it starts a Step Functions execution with the S3 bucket and key as input:

```json
{
  "detail": {
    "bucket": {"name": "ai-dp-data-lake-dev-us-west-2"},
    "object": {"key": "raw/year=2026/month=01/day=25/49670192...json"}
  }
}
```

### Step 4 — Step Functions orchestrates AI enrichment

The state machine (`ai-dp-dev-orchestrator`) runs 6 states:

| State | Type | What it does |
|-------|------|-------------|
| PrepareComprehendInput | Pass | Extracts bucket + key from EventBridge event |
| ReadS3Object | Task | Calls `s3:GetObject` to read file contents |
| PrepareTextContent | Pass | Packages text for Comprehend input |
| ComprehendAnalysis | Parallel | Runs DetectSentiment + DetectEntities simultaneously |
| FormatResults | Pass | Merges both Comprehend outputs with source metadata |
| InvokeMergeLambda | Task | Calls Merge Lambda with enriched payload |

The Parallel state runs both Comprehend calls concurrently, cutting enrichment time roughly in half vs. sequential execution.

**Retry policy on InvokeMergeLambda:**
- Errors: `Lambda.ServiceException`, `Lambda.TooManyRequestsException`
- MaxAttempts: 3, Interval: 2s, BackoffRate: 2.0

**On failure:** State machine transitions to `MergeFailed` (Fail state). Check CloudWatch Logs for the execution ARN and the SQS DLQ for the original record.

### Step 5 — Comprehend AI analysis

Two calls run in parallel, both targeting `us-west-2`:

**DetectSentiment** returns:
```json
{
  "Sentiment": "POSITIVE",
  "SentimentScore": {"Positive": 0.9987, "Negative": 0.0003, "Neutral": 0.0008, "Mixed": 0.0002}
}
```

**DetectEntities** returns:
```json
{
  "Entities": [
    {"Text": "dashboard", "Type": "OTHER", "Score": 0.9823},
    {"Text": "user-123", "Type": "PERSON", "Score": 0.7541}
  ]
}
```

### Step 6 — Merge Lambda writes to three destinations

The Merge Lambda receives the enriched payload and writes to all three storage targets:

**S3 processed/** — Full enriched record:
```json
{
  "recordId": "uuid-v4",
  "event_type": "page_view",
  "event_timestamp": "2026-01-25T12:00:00Z",
  "sentiment": "POSITIVE",
  "sentiment_scores": {"positive": 0.9987, ...},
  "entities": [{"text": "dashboard", "type": "OTHER", "score": 0.9823}],
  "processing_metadata": {"pipeline_version": "1.0", "processed_at": "2026-01-25T12:00:05Z"}
}
```

Key: `processed/year=YYYY/month=MM/day=DD/{uuid}.json`

**DynamoDB** — Hot store for recent records:
- PK: `recordId` (UUID)
- SK: `timestamp` (ISO 8601)
- GSI: `recordType-timestamp-index` for time-range queries by event type
- TTL: 30 days (auto-deleted by DynamoDB)
- PITR: enabled (35-day recovery window)

**S3 curated/** — Running aggregate summary:
```json
{
  "total_records": 1042,
  "sentiment_counts": {"POSITIVE": 731, "NEGATIVE": 187, "NEUTRAL": 124},
  "top_entities": [{"text": "dashboard", "count": 412}, ...],
  "last_updated": "2026-01-25T12:00:05Z"
}
```

Key: `curated/latest_summary.json` (single object, overwritten on each record — no accumulation)

The Merge Lambda uses a custom `DecimalEncoder` for all JSON serialization. This prevents Python floats from serializing as scientific notation (e.g., `9.999e-01`), which causes `HIVE_CURSOR_ERROR` in Athena. See `docs/errorlog.md` for details.

---

## Analytics Layer

Three data sources feed the dashboard, each with different latency and query complexity trade-offs:

| Source | Latency | Use Case |
|--------|---------|----------|
| DynamoDB | ~50ms | Real-time recent records, individual lookups |
| S3 curated/ | ~100ms | Pre-aggregated totals (sentiment counts, top entities) |
| Athena | ~3s | Ad-hoc SQL over full historical dataset |

**Glue Crawler** (`ai-dp-dev-crawler`) scans `processed/` and updates the Glue Data Catalog (`ai-dp-dev-analytics`) with the current schema and partition list. Athena queries the catalog.

**Dashboard** (`dashboard/index.html`) is a vanilla HTML + Chart.js app that queries all three sources on load and renders:
- Sentiment distribution pie chart (from DynamoDB or curated/)
- Entity frequency bar chart (from curated/)
- Recent records table (from DynamoDB)
- Ad-hoc Athena query interface

---

## Data Retention Summary

| Storage | Retention | Why |
|---------|-----------|-----|
| S3 raw/ | 180 days | Source of truth for replay; moderate retention cost |
| S3 processed/ | 365 days | Full enriched dataset for historical Athena queries |
| S3 curated/ | Indefinite | Single small file; no cost pressure |
| DynamoDB | 30 days (TTL) | Hot queries only need recent data; TTL keeps costs predictable |
| DynamoDB PITR | 35 days | Point-in-time recovery for accidental deletion |

---

## Observability

| Signal | Where |
|--------|-------|
| ETL Lambda failures | SQS DLQ: `ai-dp-dev-etl-dlq` + CloudWatch Logs |
| Merge Lambda failures | SQS DLQ: `ai-dp-dev-merge-dlq` + CloudWatch Logs |
| Step Functions failures | CloudWatch Logs: `/aws/states/ai-dp-dev-orchestrator` |
| Pipeline metrics | CloudWatch Dashboard: `ai-dp-dev-operations` |
| Threshold alerts | 6 CloudWatch Alarms → SNS → email |

**Key alarms:** Lambda error rate > 5%, Kinesis iterator age > 60s, Step Functions failure count > 0, DLQ message count > 0.
