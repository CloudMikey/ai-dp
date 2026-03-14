# Pipeline Summary — Implementation Review

A quick-reference guide to every section of the pipeline in architectural order: what was built, which resources were used, and why.

---

## 1. Bootstrap — Remote State

**Module:** `bootstrap/`

We created an S3 bucket (`tf-state-aidp`) in `us-west-1` to store Terraform state remotely. This means the state file isn't on your local machine — it lives in AWS so any machine or CI/CD system can use it. We enabled native S3 locking (`use_lockfile = true`) so two people can't apply at the same time.

**Resources:**
- `aws_s3_bucket` — holds the `.tfstate` file
- Backend config (`backend "s3"`) — tells Terraform to read/write state from that bucket

---

## 2. Data Lake — S3 Foundation

**Module:** `modules/data_lake/`

We created a single S3 bucket (`ai-dp-data-lake-dev-us-west-2`) with three logical layers using prefixes: `raw/`, `processed/`, and `curated/`. Raw is untouched ingested data, processed is AI-enriched data, curated is pre-aggregated data for the dashboard.

**Resources:**
- `aws_s3_bucket` — the bucket itself
- `aws_s3_bucket_versioning` — keeps previous versions of objects in case of accidental overwrites
- `aws_s3_bucket_server_side_encryption_configuration` — encrypts all objects at rest automatically
- `aws_s3_bucket_public_access_block` — blocks all public access, no exceptions
- `aws_s3_bucket_lifecycle_configuration` — automatically deletes old objects (180 days raw, 365 days processed) to control cost
- `aws_s3_bucket_policy` — enforces TLS so data can only be transmitted over encrypted connections
- `aws_s3_bucket_notification` — sends EventBridge events whenever a new object is uploaded (triggers the batch path)

---

## 3. Streaming Ingestion — API Gateway + Kinesis + ETL Lambda

**Module:** `modules/ingestion_stream/`

This is the streaming path: a client sends a POST request, API Gateway forwards it directly to Kinesis, and the ETL Lambda picks it up and writes to S3 `raw/`.

### API Gateway

- `aws_apigatewayv2_api` — creates the HTTP API entry point (`protocol_type = "HTTP"`)
- `aws_apigatewayv2_integration` — wires the API to Kinesis `PutRecord` directly using `AWS_PROXY`, mapping the request body to Kinesis `Data` and the `X-Partition-Key` header to the Kinesis `PartitionKey`. No Lambda needed here.
- `aws_apigatewayv2_route` — binds `POST /ingest` to the integration so incoming requests know where to go
- `aws_apigatewayv2_stage` — deploys the API with `$default` stage and `auto_deploy = true` so it's publicly reachable

### Kinesis

- `aws_kinesis_stream` — the stream buffer that holds incoming records for up to 24 hours. Decouples ingestion speed from processing speed. KMS encrypted.

### ETL Lambda

- `aws_lambda_function` (`etl`) — polls Kinesis, decodes the base64 data, validates and normalizes it, writes to S3 `raw/` with date partitioning (`year=YYYY/month=MM/day=DD/`). Idempotent — uses the Kinesis sequence number as the filename.
- `aws_lambda_event_source_mapping` — connects Kinesis to the ETL Lambda so it triggers automatically when records appear
- `aws_sqs_queue` (ETL DLQ) — catches any records the Lambda fails to process so nothing is lost
- `aws_cloudwatch_log_group` — stores Lambda logs with 7-day retention

---

## 4. Batch Ingestion — EventBridge

**Module:** `modules/ingestion_stream/` (same module, batch path)

When a file is uploaded directly to S3 `raw/`, EventBridge detects it and triggers Step Functions. This is the batch path — no API Gateway involved.

**Resources:**
- `aws_cloudwatch_event_rule` — listens for S3 `ObjectCreated` events filtered to the `raw/` prefix only
- `aws_cloudwatch_event_target` — points the rule at the Step Functions state machine

---

## 5. Orchestration — Step Functions

**Module:** `modules/step_functions/`

Step Functions is the brain of the batch path. It receives the S3 event from EventBridge and orchestrates the AI enrichment steps in sequence and in parallel.

**Resources:**
- `aws_sfn_state_machine` — the state machine definition (`ai-dp-dev-orchestrator`). Calls Comprehend sentiment and entity extraction in parallel (two tasks at the same time), then passes results to the Merge Lambda.
- `aws_cloudwatch_log_group` — logs every state transition at `ALL` level for debugging

Why Step Functions instead of just Lambda? It gives you visual execution history, built-in retry logic, catch blocks for errors, and parallel execution — all without writing that orchestration code yourself.

---

## 6. AI Enrichment — Amazon Comprehend

**Integrated into Step Functions (no separate module)**

Comprehend runs directly from the Step Functions state machine using AWS SDK integrations — no Lambda wrapper needed. Two tasks run in parallel:

- **Sentiment analysis** — returns `POSITIVE`, `NEGATIVE`, `NEUTRAL`, or `MIXED` with a confidence score
- **Entity extraction** — returns named entities (people, places, organizations, etc.) found in the text

IAM is scoped to `s3:GetObject` on `raw/*` only — least privilege.

---

## 7. Merge Lambda — Write to Both Stores

**Module:** `modules/orchestration/`

After Comprehend finishes, the Merge Lambda combines the original event data with the AI results and writes to two places simultaneously.

**Resources:**
- `aws_lambda_function` (`merge`) — reads the original S3 object, merges sentiment + entities, writes to:
  - S3 `processed/` with date partitioning (data lake, for Athena)
  - DynamoDB (hot store, for the live dashboard)
  - S3 `curated/` (pre-aggregated sentiment counts, for instant dashboard loads)
- `aws_sqs_queue` (Merge DLQ) — catches failures so no records are silently dropped
- `aws_cloudwatch_log_group` — 7-day log retention

---

## 8. Hot Store — DynamoDB

**Module:** `modules/hot_store/`

DynamoDB holds the last 30 days of enriched records for fast, low-latency dashboard queries.

**Resources:**
- `aws_dynamodb_table` — the table (`ai-dp-dev-enriched-data`) with:
  - Partition key: `recordId`, Sort key: `timestamp`
  - GSI (`timestamp-index`) on `recordType + timestamp` for filtered queries
  - TTL set to 30 days — records expire automatically, no manual cleanup
  - PITR (Point-in-Time Recovery) — 35-day backup window
  - On-demand billing — no capacity to manage, 500x cheaper than provisioned for sporadic dev workloads

---

## 9. Analytics — Glue + Athena

**Module:** `modules/analytics/`

Glue crawls the S3 `processed/` layer and builds a schema. Athena uses that schema to run SQL queries against the raw files in S3 — no database to manage.

**Resources:**
- `aws_glue_catalog_database` — the metadata database (`ai-dp-dev-analytics`)
- `aws_glue_crawler` — scans S3 `processed/` and infers the schema automatically, writing it to the Glue catalog
- `aws_athena_workgroup` — the query execution environment (`ai-dp-dev-workgroup`)
- `aws_s3_bucket` (Athena results) — stores Athena query results (required by Athena)
- Supporting S3 configs — encryption, versioning, lifecycle (30-day result retention), public access block

---

## 10. Dashboard — Static Frontend

**Location:** `dashboard/`

A browser-based dashboard built with vanilla HTML/CSS/JS and Chart.js. No server — runs from the file system or S3 static hosting. Queries AWS directly using the AWS SDK for JavaScript.

**Data strategy (optimized for speed and cost):**

| Widget | Source | Latency | Why |
|--------|--------|---------|-----|
| Sentiment pie chart | Curated S3 | ~100ms | Pre-aggregated by Merge Lambda |
| Total processed | Curated S3 | ~100ms | Pre-calculated, instant |
| Entity doughnut chart | Athena | ~3s | Demonstrates UNNEST SQL skill |
| Metrics cards (counts) | DynamoDB | ~50ms | Real-time, last 30 days |
| Recent events table | DynamoDB | ~50ms | Real-time, last 30 days |

---

## 11. Observability — CloudWatch

**Module:** `modules/observability/`

Monitoring and alerting for the full pipeline.

**Resources:**
- `aws_cloudwatch_dashboard` — 8 widgets monitoring Lambda invocations/errors, Kinesis iterator age, Step Functions executions, DLQ depths, DynamoDB reads
- `aws_sns_topic` — notification channel (`ai-dp-dev-cloudwatch-alarms`)
- `aws_sns_topic_subscription` — sends alarm emails to a configured address
- 6x `aws_cloudwatch_metric_alarm`:
  - ETL Lambda error rate
  - Merge Lambda error rate
  - ETL DLQ depth
  - Merge DLQ depth
  - Kinesis iterator age (lag indicator)
  - Step Functions failures

---

## 12. Cost Management — AWS Budgets

**Module:** `modules/cost_management/`

**Resources:**
- `aws_budgets_budget` — $50/month budget with three alert thresholds:
  - 80% actual ($40) — early warning
  - 100% actual ($50) — hard limit hit
  - 100% forecasted — warns before you hit the limit

Current actual cost: ~$12/month. Kinesis is 91% of that ($10.87).

---

## Full Pipeline Flow (End to End)

```
STREAMING PATH:
Client → POST /ingest → API Gateway → Kinesis → ETL Lambda → S3 raw/
                                                                   ↓
                                                            EventBridge
                                                                   ↓
BATCH PATH:                                              Step Functions
S3 upload → EventBridge ────────────────────────────→  Step Functions
                                                                   ↓
                                                    Comprehend (parallel)
                                                    Sentiment + Entities
                                                                   ↓
                                                          Merge Lambda
                                                         ↙           ↘
                                                   DynamoDB       S3 processed/
                                                   (30 days)      + curated/
                                                       ↓               ↓
                                                   Dashboard        Athena
```

Every resource in the pipeline has a DLQ for error handling, CloudWatch logs with 7-day retention, and least-privilege IAM roles.
