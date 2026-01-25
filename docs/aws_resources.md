# AWS Resources Guide - AI-DP Pipeline

> **A comprehensive explanation of every AWS service used in this project, including why I chose them, tradeoffs, and interview preparation.**

---

## Table of Contents

1. [Resource Overview](#resource-overview)
2. [Storage Services](#storage-services)
   - [Amazon S3](#amazon-s3)
   - [Amazon DynamoDB](#amazon-dynamodb)
3. [Data Ingestion Services](#data-ingestion-services)
   - [Amazon API Gateway](#amazon-api-gateway)
   - [Amazon Kinesis Data Streams](#amazon-kinesis-data-streams)
   - [Amazon EventBridge](#amazon-eventbridge)
4. [Compute Services](#compute-services)
   - [AWS Lambda](#aws-lambda)
   - [AWS Step Functions](#aws-step-functions)
5. [AI/ML Services](#aiml-services)
   - [Amazon Comprehend](#amazon-comprehend)
6. [Analytics Services](#analytics-services)
   - [AWS Glue](#aws-glue)
   - [Amazon Athena](#amazon-athena)
7. [Monitoring & Error Handling](#monitoring--error-handling)
   - [Amazon CloudWatch](#amazon-cloudwatch)
   - [Amazon SQS (Dead Letter Queues)](#amazon-sqs-dead-letter-queues)
8. [Security & Identity](#security--identity)
   - [AWS IAM](#aws-iam)
9. [Resource Inventory](#resource-inventory)
10. [Cost Optimization Strategies](#cost-optimization-strategies)
11. [Interview Questions & Answers](#interview-questions--answers)

---

## Resource Overview

This project uses **8 core AWS services** with **30+ individual resources**:

| Service | Purpose in Pipeline | Billing Model |
|---------|---------------------|---------------|
| **S3** | Data lake storage (raw/processed/curated) | Pay per GB stored + requests |
| **DynamoDB** | Hot store for real-time queries | Pay per request (on-demand) |
| **API Gateway** | HTTP endpoint for streaming ingestion | Pay per million requests |
| **Kinesis** | Real-time data stream buffering | Pay per shard-hour + data |
| **EventBridge** | Event routing for batch ingestion | Pay per million events |
| **Lambda** | Serverless compute (ETL, Merge) | Pay per invocation + duration |
| **Step Functions** | Workflow orchestration | Pay per state transition |
| **Comprehend** | AI sentiment & entity extraction | Pay per unit analyzed |
| **Glue** | Data catalog & schema discovery | Pay per DPU-hour (crawler) |
| **Athena** | SQL queries on S3 data | Pay per TB scanned |
| **CloudWatch** | Logging and monitoring | Pay per GB ingested |
| **SQS** | Dead letter queues for failures | Pay per million requests |
| **IAM** | Access control & permissions | Free |

---

## Storage Services

### Amazon S3

#### What It Is
Amazon Simple Storage Service (S3) is object storage with virtually unlimited capacity. Objects are stored in "buckets" and accessed via unique keys (paths).

#### How I Use It
I implemented a **three-layer data lake** (medallion architecture):

```
ai-dp-data-lake-dev-us-west-2/
├── raw/           # Bronze layer - ingested data as-is
├── processed/     # Silver layer - AI-enriched data
└── curated/       # Gold layer - pre-aggregated summaries
```

**Key Configurations:**
- **Versioning**: Enabled (recover from accidental deletions)
- **Encryption**: AES256 server-side encryption at rest
- **Public Access Block**: All 4 settings enabled (no public access)
- **Bucket Policy**: Denies non-HTTPS requests (TLS enforced)
- **EventBridge Notifications**: Enabled for batch ingestion detection

#### Lifecycle Policies (Cost Optimization)

| Layer | Standard | Intelligent-Tiering | Glacier | Expiration |
|-------|----------|---------------------|---------|------------|
| Raw | 0-30 days | 30-90 days | 90-180 days | 180 days |
| Processed | 0-60 days | 60-120 days | 120-365 days | 365 days |
| Curated | Forever | - | - | Never |

**Why different policies?**
- **Raw**: Kept shortest - it's the source of truth but rarely queried after processing
- **Processed**: Kept longer - this is what Athena queries for analytics
- **Curated**: Permanent - pre-computed summaries are small and always needed

#### Why I Chose S3

**Benefits:**
- 11 9's durability (99.999999999%) - data is virtually never lost
- Virtually unlimited storage capacity
- Native integration with Athena, Glue, Lambda, EventBridge
- Fine-grained access control via bucket policies and IAM
- Cost-effective for large datasets (especially with lifecycle policies)

**Tradeoffs:**
- Eventually consistent for overwrite PUTs (though now strongly consistent for all operations as of Dec 2020)
- No native querying (need Athena/Redshift Spectrum)
- Object storage, not file system (can't append to files)
- API charges add up with high request volumes

#### S3 Partitioning Strategy

I use **Hive-style partitioning** for Athena query optimization:

```
processed/year=2026/month=01/day=24/record-uuid.json
```

**Why this matters:**
```sql
-- This query only scans January 2026 data (partition pruning)
SELECT * FROM processed
WHERE year = '2026' AND month = '01'
```

Without partitioning, Athena would scan ALL data. With partitioning:
- **90%+ cost reduction** (only scan relevant partitions)
- **10x faster queries** (less data to read)

#### Interview Points - S3

1. **"Explain the medallion architecture."**
   > "It's a data lake pattern with three layers: Bronze (raw data as-is), Silver (cleaned/enriched), and Gold (aggregated/business-ready). Each layer has different retention policies because their access patterns differ."

2. **"Why not just use one S3 bucket?"**
   > "I use one bucket with prefixes (raw/, processed/, curated/) rather than multiple buckets because it simplifies IAM policies and cross-layer data movement. The prefixes act as logical separators with different lifecycle rules."

3. **"How do you prevent accidental data loss?"**
   > "Versioning is enabled, so deleted objects can be recovered. Lifecycle rules only apply to current versions. The bucket policy denies destructive actions from most principals."

4. **"What's the difference between S3 Standard, Intelligent-Tiering, and Glacier?"**
   > "Standard: Frequent access, highest cost (~$0.023/GB). Intelligent-Tiering: Auto-moves between tiers based on access patterns (~$0.0125/GB). Glacier: Archive storage, retrieval takes minutes-hours (~$0.004/GB). I use lifecycle rules to automatically transition data as it ages."

---

### Amazon DynamoDB

#### What It Is
DynamoDB is a fully managed NoSQL database with single-digit millisecond latency at any scale. It's a key-value and document database.

#### How I Use It
DynamoDB serves as the **hot store** for real-time dashboard queries (last 30 days of data).

**Table: `ai-dp-dev-enriched-data`**

| Attribute | Type | Role |
|-----------|------|------|
| `recordId` | String | Partition Key (unique identifier) |
| `timestamp` | Number | Sort Key (milliseconds since epoch) |
| `recordType` | String | GSI hash key (e.g., "text") |
| `sentiment` | String | POSITIVE, NEGATIVE, NEUTRAL, MIXED |
| `sentimentScore` | Number | Confidence score (0.0-1.0) |
| `entities` | List | Extracted entities ["AWS", "Lambda"] |
| `textPreview` | String | First 500 chars of original text |
| `expiresAt` | Number | TTL timestamp (auto-delete after 30 days) |

**Global Secondary Index (GSI): `timestamp-index`**
- Hash Key: `recordType`
- Range Key: `timestamp`
- Purpose: Query records by type within a time range

#### Key Features Configured

**1. On-Demand Billing (PAY_PER_REQUEST)**
```hcl
billing_mode = "PAY_PER_REQUEST"
```
- No capacity planning needed
- Auto-scales to any traffic level
- Pay only for what you use
- Perfect for unpredictable/development workloads

**2. TTL (Time-To-Live)**
```hcl
ttl {
  attribute_name = "expiresAt"
  enabled        = true
}
```
- Records auto-delete after 30 days
- No manual cleanup needed
- Reduces storage costs automatically
- TTL deletions don't count against write capacity

**3. Point-in-Time Recovery (PITR)**
```hcl
point_in_time_recovery {
  enabled = true
}
```
- Continuous backups for 35 days
- Restore to any second within the window
- Protection against accidental deletes

#### Why I Chose DynamoDB

**Benefits:**
- Single-digit millisecond latency regardless of data size
- Fully managed (no servers to patch)
- Auto-scaling with on-demand mode
- TTL for automatic data expiration
- Native AWS integration (Lambda, Step Functions, Streams)

**Tradeoffs:**
- No complex queries (no JOINs, limited filtering)
- Requires careful schema design upfront
- GSI costs additional storage and throughput
- On-demand is ~25% more expensive than optimized provisioned
- 400KB item size limit

#### DynamoDB vs. S3 - Why Both?

| Aspect | DynamoDB | S3 + Athena |
|--------|----------|-------------|
| Latency | 1-10ms | 2-10 seconds |
| Query Pattern | Key lookups, scans | Complex SQL, aggregations |
| Cost per Query | ~$0.00000125/read | ~$5/TB scanned |
| Data Retention | 30 days (TTL) | 365+ days |
| Use Case | Real-time dashboard | Historical analytics |

**My Strategy:** DynamoDB for "hot" recent data, S3+Athena for "cold" historical analytics.

#### Interview Points - DynamoDB

1. **"Why use both DynamoDB AND S3?"**
   > "Different access patterns need different storage. DynamoDB gives me sub-10ms latency for the dashboard's real-time metrics (last 30 days). S3+Athena handles historical analytics where 3-second latency is acceptable. The Merge Lambda writes to both simultaneously."

2. **"Why on-demand instead of provisioned capacity?"**
   > "For a portfolio project with unpredictable traffic, on-demand is safer—no throttling risk, no capacity planning. In production with steady traffic, I'd switch to provisioned with auto-scaling for the ~25% cost savings."

3. **"Explain your partition key choice."**
   > "I use `recordId` (timestamp-uuid format) as the partition key because it's unique and has high cardinality, distributing writes evenly across partitions. Using just `timestamp` would create hot partitions during traffic spikes."

4. **"What's the GSI for?"**
   > "The GSI on `recordType + timestamp` enables queries like 'get all text records from the last 7 days' without scanning the entire table. It's an inverted index that supports different access patterns than the base table."

5. **"How does TTL work?"**
   > "DynamoDB checks the `expiresAt` attribute against the current time. Items past their TTL are marked for deletion and removed within 48 hours. The deletions are eventually consistent and don't consume write capacity—it's essentially free cleanup."

---

## Data Ingestion Services

### Amazon API Gateway

#### What It Is
API Gateway is a fully managed service for creating, publishing, and securing APIs at any scale. It handles request routing, throttling, authentication, and more.

#### How I Use It
I use **HTTP API** (not REST API) for streaming data ingestion:

```
POST https://abc123.execute-api.us-west-2.amazonaws.com/ingest
```

**Key Configuration:**
- **Protocol**: HTTP API (lighter, cheaper than REST API)
- **Integration**: Direct AWS service integration to Kinesis (no Lambda proxy)
- **Route**: `POST /ingest` → Kinesis PutRecord
- **Stage**: `$default` with auto-deploy

#### Direct Kinesis Integration (No Lambda)

Instead of: `API Gateway → Lambda → Kinesis`
I use: `API Gateway → Kinesis` (direct)

**Benefits:**
- Lower latency (one less hop)
- Lower cost (no Lambda invocation charge)
- Higher throughput (API Gateway handles more RPS)
- Simpler architecture

**Tradeoffs:**
- Less flexibility for request validation
- No custom business logic before Kinesis
- Harder to debug (no Lambda logs for ingestion layer)

#### HTTP API vs. REST API

| Feature | HTTP API | REST API |
|---------|----------|----------|
| Cost | ~70% cheaper | Full price |
| Latency | Lower | Higher |
| Features | Basic | Full (caching, WAF, etc.) |
| Use Case | Simple proxy | Enterprise APIs |

**My Choice:** HTTP API because I only need simple request forwarding to Kinesis.

#### Interview Points - API Gateway

1. **"Why HTTP API instead of REST API?"**
   > "HTTP APIs are ~70% cheaper and have lower latency. I don't need REST API features like response caching, request validation templates, or AWS WAF integration. For a simple Kinesis proxy, HTTP API is the right choice."

2. **"Why direct Kinesis integration instead of Lambda?"**
   > "Direct integration removes Lambda from the hot path, reducing latency and cost. The ingestion layer should be fast and cheap—complex validation happens downstream in the ETL Lambda after Kinesis buffering."

3. **"How do you handle authentication?"**
   > "Currently using API keys for simplicity. In production, I'd add JWT authorizers with Cognito or implement IAM authentication for service-to-service calls."

---

### Amazon Kinesis Data Streams

#### What It Is
Kinesis Data Streams is a real-time data streaming service that can capture gigabytes of data per second from hundreds of thousands of sources.

#### How I Use It
Kinesis sits between API Gateway and the ETL Lambda, providing:
- **Buffering**: Absorbs traffic spikes
- **Durability**: 24-hour retention (replay capability)
- **Ordering**: Records within a shard are ordered by arrival time

**Configuration:**
```hcl
stream_name      = "ai-dp-dev-ingestion-stream"
shard_count      = 1           # 1 MB/sec write, 2 MB/sec read
retention_period = 24          # hours
stream_mode      = "PROVISIONED"
```

#### Key Concepts

**Shards:**
- Unit of capacity (1 shard = 1 MB/s write, 2 MB/s read)
- Records are distributed across shards by partition key
- More shards = more parallelism = higher cost

**Partition Keys:**
- Determines which shard receives a record
- Records with the same partition key go to the same shard (ordering guarantee)
- I use random keys for even distribution

**Sequence Numbers:**
- Unique identifier per record per shard
- I use these as S3 filenames for idempotent writes

#### Why I Chose Kinesis

**Benefits:**
- Decouples producers from consumers (API Gateway doesn't wait for Lambda)
- Handles traffic spikes (buffers during Lambda cold starts)
- Replay capability (re-process data if Lambda fails)
- Ordering guarantees within shards
- Native Lambda integration (event source mapping)

**Tradeoffs:**
- Cost per shard-hour even when idle (~$0.015/hour)
- 1 MB record size limit
- Complex capacity planning (shard splitting/merging)
- 7-day max retention (extended retention costs extra)

#### Kinesis vs. SQS

| Feature | Kinesis | SQS |
|---------|---------|-----|
| Ordering | Per-shard | FIFO queues only |
| Consumers | Multiple (fan-out) | Single (message deleted after read) |
| Replay | Yes (within retention) | No |
| Latency | ~200ms | ~10ms |
| Use Case | Streaming analytics | Task queues |

**My Choice:** Kinesis because I need ordering, potential future fan-out, and replay capability.

#### Interview Points - Kinesis

1. **"Why Kinesis instead of SQS?"**
   > "Kinesis provides ordering guarantees and replay capability. If my ETL Lambda fails, I can re-process from the same point. SQS deletes messages after consumption, so there's no replay. Also, Kinesis supports multiple consumers reading the same data (fan-out)."

2. **"How do you handle Lambda failures with Kinesis?"**
   > "The event source mapping has built-in retry logic. If Lambda fails, Kinesis retries up to 3 times before sending the failed batch to a DLQ. The iterator position only advances after successful processing."

3. **"What's the partition key strategy?"**
   > "I use random partition keys (or record IDs) to distribute load evenly across shards. If I used a customer ID, one busy customer could overload a single shard while others sit idle."

4. **"How do you achieve idempotent writes?"**
   > "I use Kinesis sequence numbers as S3 filenames instead of UUIDs. On retry, the same sequence number produces the same filename, overwriting the previous attempt. No duplicates."

---

### Amazon EventBridge

#### What It Is
EventBridge is a serverless event bus that connects applications using events. It routes events from sources (like S3) to targets (like Step Functions) based on rules.

#### How I Use It
EventBridge detects S3 batch uploads and triggers the Step Functions workflow:

```
S3 Object Created (raw/) → EventBridge Rule → Step Functions
```

**Event Pattern:**
```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {"name": ["ai-dp-data-lake-dev-us-west-2"]},
    "object": {"key": [{"prefix": "raw/"}]}
  }
}
```

**Critical Filter:** Only `raw/` prefix triggers the workflow. This prevents infinite loops—when Step Functions writes to `processed/`, it doesn't trigger another execution.

#### Why I Chose EventBridge

**Benefits:**
- Native S3 integration (no Lambda needed to detect uploads)
- Rich filtering (bucket, prefix, suffix, metadata)
- Multiple targets from one event (fan-out)
- Schema registry for event validation
- Archive and replay capability

**Tradeoffs:**
- Eventually consistent (events may arrive out of order)
- No guaranteed delivery (at-least-once, not exactly-once)
- Limited transformation capabilities (use input transformers)
- 256 KB event size limit

#### EventBridge vs. S3 Event Notifications

| Feature | EventBridge | S3 Notifications |
|---------|-------------|------------------|
| Filtering | Rich (any JSON field) | Basic (prefix, suffix) |
| Targets | 20+ services | SNS, SQS, Lambda only |
| Replays | Yes (with archive) | No |
| Cross-account | Yes | Limited |

**My Choice:** EventBridge for richer filtering and direct Step Functions integration.

#### Interview Points - EventBridge

1. **"How do you prevent infinite loops?"**
   > "The event pattern filters to `raw/` prefix only. When the Merge Lambda writes to `processed/`, no event fires. This is critical—without the filter, each write would trigger another workflow execution."

2. **"Why EventBridge instead of S3 notifications?"**
   > "EventBridge supports direct Step Functions targets without needing a Lambda intermediary. It also has richer filtering—I can filter by any JSON field in the event, not just prefix/suffix."

3. **"How do you handle duplicate events?"**
   > "EventBridge is at-least-once delivery, so duplicates are possible. My pipeline is idempotent—processing the same S3 object twice produces the same output. DynamoDB uses recordId as the partition key, so duplicates just overwrite."

---

## Compute Services

### AWS Lambda

#### What It Is
Lambda is serverless compute that runs code in response to events. You don't manage servers—AWS handles scaling, patching, and availability.

#### How I Use It

**1. ETL Lambda (`ai-dp-dev-etl`)**
- **Trigger**: Kinesis event source mapping
- **Purpose**: Validate, normalize, partition data → write to S3 `raw/`
- **Runtime**: Python 3.11
- **Memory**: 256 MB
- **Timeout**: 60 seconds

**Key Features:**
- Batch processing (up to 100 records per invocation)
- Idempotent writes using Kinesis sequence numbers
- Automatic retries (3 attempts before DLQ)

**2. Merge Lambda (`ai-dp-dev-merge`)**
- **Trigger**: Step Functions invocation
- **Purpose**: Combine AI results → write to S3 `processed/` + DynamoDB
- **Runtime**: Python 3.11
- **Memory**: 256 MB
- **Timeout**: 60 seconds

**Key Features:**
- Dual storage (S3 + DynamoDB simultaneously)
- Updates curated summary for instant dashboard loading
- Custom JSON encoder to avoid scientific notation (Athena compatibility)

#### Lambda Configuration Best Practices

**Memory Allocation:**
- More memory = more CPU = faster execution
- 256 MB is cost-effective for I/O-bound operations
- Would increase for CPU-intensive processing

**Timeout:**
- 60 seconds provides buffer for retries
- Never set to 15 minutes (max) unless truly needed
- Timeout triggers retry, wasting resources

**Environment Variables:**
```python
DATA_LAKE_BUCKET = os.environ.get('DATA_LAKE_BUCKET')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE')
TTL_DAYS = int(os.environ.get('TTL_DAYS', '30'))
```
- No hardcoded values in code
- Environment-specific via Terraform variables

#### Why I Chose Lambda

**Benefits:**
- Zero server management
- Auto-scaling (0 to thousands of concurrent executions)
- Pay-per-use (idle cost = $0)
- Native integration with Kinesis, S3, Step Functions
- Built-in retry mechanisms

**Tradeoffs:**
- Cold starts (100-300ms for first invocation)
- 15-minute timeout limit
- 10 GB memory limit
- Stateless (no persistent connections)
- Vendor lock-in

#### Interview Points - Lambda

1. **"How do you handle cold starts?"**
   > "For streaming ingestion, cold starts are negligible because Kinesis batches records. The ETL Lambda stays warm with consistent traffic. For latency-sensitive paths, I'd use provisioned concurrency to keep instances warm."

2. **"Why 256 MB memory?"**
   > "These Lambdas are I/O bound (reading from Kinesis, writing to S3/DynamoDB). More memory gives more CPU, but I/O operations don't benefit much. 256 MB is cost-effective for this workload. I'd increase it for CPU-intensive transformations."

3. **"How do you ensure idempotency?"**
   > "The ETL Lambda uses Kinesis sequence numbers as S3 filenames. On retry, the same sequence number writes to the same file, overwriting the previous attempt. No duplicates created."

4. **"What happens when Lambda fails?"**
   > "For Kinesis-triggered Lambdas, failed batches retry up to 3 times. After exhausting retries, the batch goes to the SQS Dead Letter Queue. I can inspect failed records and replay them manually."

---

### AWS Step Functions

#### What It Is
Step Functions is a serverless orchestration service that lets you coordinate multiple AWS services into workflows defined as state machines.

#### How I Use It
Step Functions orchestrates the AI enrichment pipeline:

```
┌─────────────────────────────────────────────────────────────────┐
│                    ai-dp-dev-orchestrator                        │
├─────────────────────────────────────────────────────────────────┤
│  PrepareComprehendInput (Pass)                                   │
│       ↓                                                          │
│  ReadS3Object (Task: s3:getObject)                              │
│       ↓                                                          │
│  PrepareTextContent (Pass)                                       │
│       ↓                                                          │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  ComprehendAnalysis (Parallel)                           │    │
│  │  ┌──────────────────┐  ┌───────────────────┐            │    │
│  │  │ DetectSentiment  │  │  DetectEntities   │            │    │
│  │  │ (Task: Comprehend)│  │ (Task: Comprehend)│            │    │
│  │  └──────────────────┘  └───────────────────┘            │    │
│  └─────────────────────────────────────────────────────────┘    │
│       ↓                                                          │
│  FormatResults (Pass)                                            │
│       ↓                                                          │
│  InvokeMergeLambda (Task: lambda:invoke)                        │
│       ↓                                                          │
│  MergeComplete (Succeed) / MergeFailed (Fail)                   │
└─────────────────────────────────────────────────────────────────┘
```

#### Key Features Used

**1. AWS SDK Integrations**
```json
{
  "Type": "Task",
  "Resource": "arn:aws:states:::aws-sdk:s3:getObject",
  "Parameters": {
    "Bucket.$": "$.bucket",
    "Key.$": "$.key"
  }
}
```
- Direct S3 and Comprehend calls without Lambda wrappers
- Reduces code, cost, and latency

**2. Parallel State**
```json
{
  "Type": "Parallel",
  "Branches": [
    { "States": { "DetectSentiment": {...} } },
    { "States": { "DetectEntities": {...} } }
  ]
}
```
- DetectSentiment and DetectEntities run simultaneously
- 50% faster than sequential execution

**3. Error Handling**
```json
{
  "Retry": [
    {
      "ErrorEquals": ["States.ALL"],
      "MaxAttempts": 3,
      "BackoffRate": 2.0
    }
  ],
  "Catch": [
    {
      "ErrorEquals": ["States.ALL"],
      "Next": "MergeFailed"
    }
  ]
}
```
- Automatic retries with exponential backoff
- Catch blocks route failures to specific states

**4. CloudWatch Logs**
```hcl
logging_configuration {
  level                  = "ALL"
  include_execution_data = true
  log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
}
```
- Full execution history for debugging
- State transitions, inputs, outputs all logged

#### Why I Chose Step Functions

**Benefits:**
- Visual workflow (state machine diagram)
- Built-in retry with exponential backoff
- Parallel execution support
- AWS SDK integrations (no Lambda wrappers)
- Execution history for debugging
- Long-running workflows (up to 1 year)

**Tradeoffs:**
- Cost per state transition ($0.025 per 1000 transitions)
- Complex ASL JSON syntax
- Limited expression language (JSONPath)
- Cold start for first execution

#### Step Functions vs. Lambda Orchestration

| Feature | Step Functions | Lambda calling Lambda |
|---------|----------------|----------------------|
| Visualization | State machine diagram | None |
| Retries | Built-in | Manual implementation |
| Parallel | Native support | Async invoke |
| Long-running | Up to 1 year | 15 min max |
| Debugging | Execution history | Log correlation |
| Cost | Per transition | Per invocation |

**My Choice:** Step Functions for complex orchestration with parallel branches and built-in error handling.

#### Interview Points - Step Functions

1. **"Why Step Functions instead of Lambda calling Lambda?"**
   > "Step Functions provides visual workflows, built-in retry logic, and parallel execution without custom code. The execution history makes debugging easy—I can see exactly which state failed and why. Lambda orchestration would require implementing all this manually."

2. **"Explain the Parallel state."**
   > "DetectSentiment and DetectEntities are independent operations. Running them in parallel cuts latency by 50%. Step Functions' Parallel state waits for all branches to complete before continuing."

3. **"How do you handle errors?"**
   > "Each task has Retry and Catch configurations. Retries use exponential backoff (3 attempts, 2x backoff). If all retries fail, Catch routes to MergeFailed state, which logs the error and marks the execution as failed."

4. **"Why AWS SDK integrations instead of Lambda?"**
   > "SDK integrations call AWS services directly from Step Functions. No Lambda cold starts, no Lambda invocation charges, less code to maintain. It's ideal for simple operations like S3 GetObject or Comprehend DetectSentiment."

---

## AI/ML Services

### Amazon Comprehend

#### What It Is
Comprehend is a natural language processing (NLP) service that uses machine learning to find insights in text. It's fully managed—no ML expertise needed.

#### How I Use It
Two Comprehend APIs called in parallel from Step Functions:

**1. DetectSentiment**
```json
{
  "Text": "AWS provides excellent cloud services!",
  "LanguageCode": "en"
}
```
Returns:
```json
{
  "Sentiment": "POSITIVE",
  "SentimentScore": {
    "Positive": 0.9876,
    "Negative": 0.0001,
    "Neutral": 0.0120,
    "Mixed": 0.0003
  }
}
```

**2. DetectEntities**
```json
{
  "Text": "AWS Lambda runs in Amazon Web Services",
  "LanguageCode": "en"
}
```
Returns:
```json
{
  "Entities": [
    {"Text": "AWS Lambda", "Type": "TITLE", "Score": 0.99},
    {"Text": "Amazon Web Services", "Type": "ORGANIZATION", "Score": 0.98}
  ]
}
```

#### Entity Types Detected

| Type | Examples |
|------|----------|
| ORGANIZATION | Companies, agencies, institutions |
| PERSON | People's names |
| LOCATION | Cities, countries, landmarks |
| DATE | Dates, times, durations |
| QUANTITY | Numbers, measurements |
| TITLE | Job titles, product names |
| COMMERCIAL_ITEM | Products, brands |
| EVENT | Events, occasions |

#### Why I Chose Comprehend

**Benefits:**
- No ML expertise required (fully managed)
- Pay-per-request (no idle cost)
- High accuracy for common NLP tasks
- Native AWS integration (Step Functions SDK)
- Supports 12+ languages

**Tradeoffs:**
- Limited customization (can't fine-tune models)
- English-centric (best accuracy for English)
- Cost adds up at scale ($0.0001 per unit)
- 5KB text limit per request
- No streaming support (batch only)

#### Comprehend vs. Custom ML

| Feature | Comprehend | Custom SageMaker |
|---------|------------|------------------|
| Setup Time | Minutes | Weeks |
| Accuracy | Good for general use | Can be optimized |
| Cost | Per request | Per endpoint hour |
| Customization | Limited | Full control |
| Use Case | Common NLP | Domain-specific |

**My Choice:** Comprehend for quick, accurate sentiment/entity extraction without ML overhead.

#### Interview Points - Comprehend

1. **"Why Comprehend instead of a custom model?"**
   > "Comprehend is serverless and requires no ML expertise. For standard sentiment analysis, its accuracy is excellent out-of-the-box. A custom SageMaker model would require training data, model tuning, and endpoint management—overkill for this use case."

2. **"How do you handle the confidence scores?"**
   > "Comprehend returns scores for all four sentiments (Positive, Negative, Neutral, Mixed). I store the dominant sentiment and its score. In the dashboard, I could filter by confidence threshold if needed."

3. **"What's the cost model?"**
   > "Comprehend charges per 'unit' (100 characters). DetectSentiment and DetectEntities are ~$0.0001 per unit. For a 500-character text, that's $0.0005 per record. At 10,000 records/month, that's ~$5/month for AI enrichment."

---

## Analytics Services

### AWS Glue

#### What It Is
Glue is a serverless data integration service for ETL (Extract, Transform, Load) and data cataloging. I use it for schema discovery, not ETL.

#### How I Use It

**1. Glue Data Catalog**
- Central metadata repository
- Stores table schemas (column names, types)
- Athena queries the catalog to understand data structure

**Database:** `ai-dp-dev-analytics`

**2. Glue Crawler**
- Scans S3 `processed/` prefix
- Infers schema from JSON files
- Detects partitions (year/month/day)
- Updates table definition automatically

**Configuration:**
```hcl
schedule = "cron(0 */6 * * ? *)"  # Every 6 hours (if scheduled)
schema_change_policy {
  update_behavior = "UPDATE_IN_DATABASE"  # Add new columns
}
```

#### Crawler-Created Table Schema

| Column | Type | Source |
|--------|------|--------|
| recordid | string | Merge Lambda |
| timestamp | bigint | Milliseconds since epoch |
| recordtype | string | Always "text" |
| sentiment | string | Comprehend |
| sentimentscore | double | Comprehend |
| sentimentscores | struct | All 4 scores |
| entities | array<string> | Entity names |
| entitydetails | array<struct> | Full entity info |
| textpreview | string | First 500 chars |
| rawdatalocation | string | S3 raw path |
| processingmetadata | struct | Lambda metadata |
| mergedat | string | ISO timestamp |
| **year** | string | Partition key |
| **month** | string | Partition key |
| **day** | string | Partition key |

#### Why I Chose Glue

**Benefits:**
- Automatic schema discovery (no manual DDL)
- Handles schema evolution (new fields added automatically)
- Partition detection (Hive-style)
- Shared catalog with Athena, Redshift, EMR
- Serverless (pay only when crawler runs)

**Tradeoffs:**
- Crawler can be slow for large datasets
- DPU-hour billing can be expensive
- Limited transformation in crawler (use Glue jobs for complex ETL)
- Schema inference sometimes wrong (need manual fixes)

#### Interview Points - Glue

1. **"Why use Glue Crawler instead of manual table definition?"**
   > "The crawler automatically detects schema changes. When I add new fields to the Merge Lambda output, the crawler adds them to the table. No manual DDL updates needed."

2. **"How does partition detection work?"**
   > "The crawler recognizes Hive-style paths like `year=2026/month=01/day=24/`. It automatically creates partition columns in the table. Athena can then prune partitions in queries."

3. **"What's the UPDATE_IN_DATABASE policy?"**
   > "It means new columns are added, but existing columns aren't deleted. This prevents breaking changes—if I remove a field from Lambda output, old data in S3 still has it."

---

### Amazon Athena

#### What It Is
Athena is a serverless SQL query engine that lets you analyze data in S3 using standard SQL. No infrastructure to manage—just point it at S3 and query.

#### How I Use It

**Workgroup:** `ai-dp-dev-workgroup`
- Enforces query result location
- Enables CloudWatch metrics
- Supports query cost controls

**Query Examples:**

```sql
-- Sentiment distribution (pie chart)
SELECT sentiment, COUNT(*) as count
FROM "ai-dp-dev-analytics"."processed"
GROUP BY sentiment

-- Entity type analysis (requires UNNEST for nested arrays)
SELECT entity.Type as entity_type, COUNT(*) as count
FROM "ai-dp-dev-analytics"."processed"
CROSS JOIN UNNEST(entitydetails) AS t(entity)
GROUP BY entity.Type
ORDER BY count DESC

-- Partition pruning (90% cost reduction)
SELECT * FROM processed
WHERE year = '2026' AND month = '01'
```

#### Key Features

**1. Partition Pruning**
```sql
WHERE year = '2026' AND month = '01'
```
- Only scans matching partitions
- Reduces data scanned by 90%+
- Directly reduces cost (charged per TB scanned)

**2. UNNEST for Nested Arrays**
```sql
CROSS JOIN UNNEST(entitydetails) AS t(entity)
```
- Flattens array into rows
- Enables aggregations on nested data
- Critical for entity analysis queries

**3. Workgroup Controls**
- Query result location enforced
- Per-query byte limits (cost control)
- CloudWatch metrics for monitoring

#### Why I Chose Athena

**Benefits:**
- Serverless (no clusters to manage)
- Pay-per-query ($5 per TB scanned)
- Standard SQL (familiar syntax)
- Native S3 integration
- Glue catalog integration

**Tradeoffs:**
- 2-10 second query latency (not real-time)
- No indexes (full partition scans)
- Limited concurrent queries (service quotas)
- JSON parsing can be slow (Parquet is faster)

#### Athena Cost Optimization

| Technique | Impact |
|-----------|--------|
| Partition pruning | 90%+ reduction |
| Columnar format (Parquet) | 30-90% reduction |
| Compression (Snappy, Gzip) | 50-70% reduction |
| Limit data scanned | Direct cost control |

**My Implementation:** JSON format with partition pruning. For production scale, I'd convert to Parquet with Glue ETL jobs.

#### Interview Points - Athena

1. **"Why Athena instead of Redshift?"**
   > "Athena is serverless with pay-per-query pricing. For a portfolio project with occasional queries, it's much cheaper than a Redshift cluster that bills hourly. If I had consistent, heavy query workloads, Redshift would be more cost-effective."

2. **"How do you optimize query costs?"**
   > "Three techniques: partition pruning (WHERE year/month/day), limiting columns (SELECT specific columns, not *), and query result caching. For production, I'd convert JSON to Parquet for columnar storage benefits."

3. **"Explain the UNNEST query."**
   > "The entitydetails column is an array of structs. UNNEST flattens it into rows, so each entity becomes a separate row. This enables GROUP BY on entity.Type to count occurrences of each entity type."

4. **"What's the latency like?"**
   > "Athena queries take 2-10 seconds depending on data size. That's why I use Curated S3 for the sentiment pie chart (instant) and DynamoDB for real-time metrics. Athena is only for complex analytics where latency is acceptable."

---

## Monitoring & Error Handling

### Amazon CloudWatch

#### What It Is
CloudWatch is AWS's monitoring and observability service. It collects logs, metrics, and events from AWS resources.

#### How I Use It

**Log Groups:**
| Log Group | Source | Retention |
|-----------|--------|-----------|
| `/aws/lambda/ai-dp-dev-etl` | ETL Lambda | 7 days |
| `/aws/lambda/ai-dp-dev-merge` | Merge Lambda | 7 days |
| `/aws/states/ai-dp-dev-orchestrator` | Step Functions | 7 days |
| `/aws/apigateway/ai-dp-dev-ingestion-api` | API Gateway | 7 days |

**Why 7-Day Retention?**
- Sufficient for debugging recent issues
- Reduces storage costs
- Production would use longer retention + S3 export

**Planned Alarms (Phase 9):**
- DLQ message count > 0
- Lambda error rate > 1%
- Step Functions failure rate > 1%
- API Gateway 5xx errors > 1%

#### Interview Points - CloudWatch

1. **"How do you debug failed executions?"**
   > "Every component logs to CloudWatch. Step Functions logs show which state failed and the error message. Lambda logs show the full stack trace. I can trace a request from API Gateway through Kinesis, Lambda, Step Functions, and back."

2. **"Why such short log retention?"**
   > "For a dev environment, 7 days is sufficient. Longer retention increases costs. In production, I'd use 30-90 day retention with S3 export for long-term storage and compliance."

---

### Amazon SQS (Dead Letter Queues)

#### What It Is
SQS is a fully managed message queue service. I use it specifically for Dead Letter Queues (DLQs) to capture failed messages.

#### How I Use It

**DLQs:**
| Queue | Source | Retention |
|-------|--------|-----------|
| `ai-dp-dev-etl-dlq` | Failed Kinesis batches | 14 days |
| `ai-dp-dev-merge-dlq` | Failed Step Functions invocations | 14 days |

**DLQ Pattern:**
```
Lambda fails 3 times → Record sent to DLQ → Manual inspection → Fix issue → Replay
```

**Why 14-Day Retention?**
- Time to investigate and fix issues
- Replay records after bug fixes
- Balance between retention and cost

#### Why SQS for DLQs

**Benefits:**
- Native Lambda DLQ integration
- Message inspection via console/CLI
- Replay capability (redrive)
- 14-day maximum retention

**Tradeoffs:**
- Manual replay process
- No built-in alerting (need CloudWatch alarm)
- Messages can expire if not processed

#### Interview Points - SQS DLQs

1. **"What happens when Lambda fails?"**
   > "After 3 retry attempts, the failed batch goes to the SQS DLQ. I can inspect the message to see the original event, fix the underlying issue, and replay the message manually or with a replay Lambda."

2. **"How do you know when messages are in the DLQ?"**
   > "CloudWatch alarm on ApproximateNumberOfMessagesVisible > 0. Any message in the DLQ triggers an alert for immediate investigation."

3. **"Why not auto-replay from DLQ?"**
   > "DLQ messages usually indicate a bug that needs human investigation. Auto-replay would just fail again. I inspect the message, fix the code, deploy, then replay manually."

---

## Security & Identity

### AWS IAM

#### What It Is
IAM (Identity and Access Management) controls who can access what in AWS. Every AWS API call is authenticated and authorized via IAM.

#### My IAM Strategy: Least Privilege

Every resource has **exactly the permissions it needs**—no more.

**Example: ETL Lambda Role**
```hcl
# Can ONLY write to raw/ prefix
{
  "Action": ["s3:PutObject"],
  "Resource": "arn:aws:s3:::ai-dp-data-lake-dev-us-west-2/raw/*"
}

# Can ONLY send to its specific DLQ
{
  "Action": ["sqs:SendMessage"],
  "Resource": "arn:aws:sqs:us-west-2:*:ai-dp-dev-etl-dlq"
}
```

**Example: Merge Lambda Role**
```hcl
# Can write to processed/ and curated/, but NOT raw/
{
  "Action": ["s3:PutObject"],
  "Resource": [
    "arn:aws:s3:::ai-dp-data-lake-dev-us-west-2/processed/*",
    "arn:aws:s3:::ai-dp-data-lake-dev-us-west-2/curated/*"
  ]
}

# Can ONLY PutItem to specific DynamoDB table
{
  "Action": ["dynamodb:PutItem"],
  "Resource": "arn:aws:dynamodb:us-west-2:*:table/ai-dp-dev-enriched-data"
}
```

#### IAM Roles in This Project

| Role | Service | Permissions |
|------|---------|-------------|
| `ai-dp-dev-apigw-kinesis-role` | API Gateway | kinesis:PutRecord |
| `ai-dp-dev-etl-lambda-role` | Lambda | s3:PutObject (raw/*), sqs:SendMessage |
| `ai-dp-dev-step-functions-role` | Step Functions | s3:GetObject, comprehend:*, lambda:Invoke |
| `ai-dp-dev-eventbridge-sfn-role` | EventBridge | states:StartExecution |
| `ai-dp-dev-merge-lambda-role` | Lambda | s3:PutObject (processed/*, curated/*), dynamodb:PutItem |
| `ai-dp-glue-crawler-role` | Glue | s3:GetObject (processed/*), glue:* |

#### Why Least Privilege Matters

**Security:**
- Compromised ETL Lambda can't access processed data
- Compromised Merge Lambda can't read raw data
- Blast radius limited to specific prefixes/tables

**Compliance:**
- Audit trail shows exactly what each service can do
- Easy to answer "who can access this data?"
- Meets SOC2, HIPAA requirements

#### Interview Points - IAM

1. **"How do you implement least privilege?"**
   > "Every IAM policy is scoped to specific resources with specific actions. S3 permissions are limited to prefixes (raw/*, processed/*). DynamoDB permissions are limited to specific tables. No wildcards on resources."

2. **"What if you need to debug a permission issue?"**
   > "IAM Access Analyzer shows unused permissions. CloudTrail logs show denied API calls with the specific permission that was missing. I add only the exact permission needed."

3. **"How do you manage IAM across environments?"**
   > "Terraform modules create environment-specific roles. Dev, staging, and prod each have their own roles with their own resource ARNs. No cross-environment access is possible."

4. **"Why separate IAM files in modules?"**
   > "I put all IAM resources in `iam.tf` within each module. This makes security reviews easier—auditors can look at one file per module to understand all permissions."

---

## Resource Inventory

### Complete AWS Resource List

| Resource Type | Name | Module |
|---------------|------|--------|
| **S3** | | |
| aws_s3_bucket | ai-dp-data-lake-dev-us-west-2 | data_lake |
| aws_s3_bucket | ai-dp-athena-results-dev-us-west-2 | analytics |
| aws_s3_bucket_versioning | (data lake) | data_lake |
| aws_s3_bucket_server_side_encryption | (both buckets) | data_lake, analytics |
| aws_s3_bucket_public_access_block | (both buckets) | data_lake, analytics |
| aws_s3_bucket_lifecycle_configuration | (both buckets) | data_lake, analytics |
| aws_s3_bucket_policy | (data lake TLS) | data_lake |
| aws_s3_bucket_notification | (EventBridge) | data_lake |
| **DynamoDB** | | |
| aws_dynamodb_table | ai-dp-dev-enriched-data | hot_store |
| **API Gateway** | | |
| aws_apigatewayv2_api | ai-dp-dev-ingestion-api | ingestion_stream |
| aws_apigatewayv2_integration | (Kinesis) | ingestion_stream |
| aws_apigatewayv2_route | POST /ingest | ingestion_stream |
| aws_apigatewayv2_stage | $default | ingestion_stream |
| **Kinesis** | | |
| aws_kinesis_stream | ai-dp-dev-ingestion-stream | ingestion_stream |
| **EventBridge** | | |
| aws_cloudwatch_event_rule | ai-dp-dev-s3-batch-ingestion | ingestion_stream |
| aws_cloudwatch_event_target | (Step Functions) | ingestion_stream |
| **Lambda** | | |
| aws_lambda_function | ai-dp-dev-etl | ingestion_stream |
| aws_lambda_function | ai-dp-dev-merge | orchestration |
| aws_lambda_event_source_mapping | (Kinesis → ETL) | ingestion_stream |
| **Step Functions** | | |
| aws_sfn_state_machine | ai-dp-dev-orchestrator | step_functions |
| **Glue** | | |
| aws_glue_catalog_database | ai-dp-dev-analytics | analytics |
| aws_glue_crawler | ai-dp-dev-crawler | analytics |
| **Athena** | | |
| aws_athena_workgroup | ai-dp-dev-workgroup | analytics |
| **SQS** | | |
| aws_sqs_queue | ai-dp-dev-etl-dlq | ingestion_stream |
| aws_sqs_queue | ai-dp-dev-merge-dlq | orchestration |
| **CloudWatch** | | |
| aws_cloudwatch_log_group | /aws/lambda/ai-dp-dev-etl | ingestion_stream |
| aws_cloudwatch_log_group | /aws/lambda/ai-dp-dev-merge | orchestration |
| aws_cloudwatch_log_group | /aws/states/ai-dp-dev-orchestrator | step_functions |
| **IAM** | | |
| aws_iam_role | ai-dp-dev-apigw-kinesis-role | ingestion_stream |
| aws_iam_role | ai-dp-dev-etl-lambda-role | ingestion_stream |
| aws_iam_role | ai-dp-dev-step-functions-role | step_functions |
| aws_iam_role | ai-dp-dev-eventbridge-sfn-role | step_functions |
| aws_iam_role | ai-dp-dev-merge-lambda-role | orchestration |
| aws_iam_role | ai-dp-glue-crawler-role | analytics |

**Total: 30+ resources across 10 AWS services**

---

## Cost Optimization Strategies

### Cost Breakdown (Estimated Dev Environment)

| Service | Monthly Cost | Optimization Applied |
|---------|--------------|---------------------|
| S3 | ~$1 | Lifecycle policies, Intelligent-Tiering |
| DynamoDB | ~$1 | On-demand, TTL auto-delete |
| Lambda | ~$1 | 256MB memory, short timeouts |
| Step Functions | ~$1 | Efficient state design |
| Kinesis | ~$10 | 1 shard (minimum) |
| Comprehend | ~$5 | Only process needed text |
| Athena | ~$1 | Partition pruning, Curated S3 |
| Glue | ~$1 | On-demand crawler |
| CloudWatch | ~$1 | 7-day retention |
| **Total** | **~$22/month** | |

### Key Optimization Techniques

1. **Lifecycle Policies**: Auto-transition to cheaper storage
2. **TTL**: Auto-delete old DynamoDB records
3. **Partition Pruning**: Scan only needed S3 partitions
4. **On-Demand Billing**: No idle capacity charges
5. **Serverless**: Scale to zero when idle
6. **Curated Layer**: Pre-compute aggregations, avoid expensive queries
7. **Short Retention**: 7-day logs, 14-day DLQ

---

## Interview Questions & Answers

### Architecture Questions

**Q: Walk me through the data flow.**
> "Data enters via API Gateway (streaming) or S3 upload (batch). Streaming data goes through Kinesis to the ETL Lambda, which validates and writes to S3 raw/. Both paths converge when EventBridge detects raw/ uploads and triggers Step Functions. The state machine reads the S3 object, calls Comprehend in parallel for sentiment and entity extraction, then invokes the Merge Lambda. Merge writes to S3 processed/ (for Athena analytics) and DynamoDB (for real-time dashboard queries). The Glue Crawler catalogs the processed data so Athena can query it."

**Q: Why two ingestion paths?**
> "Different use cases need different patterns. Streaming (API → Kinesis) handles real-time events with sub-second latency. Batch (S3 → EventBridge) handles bulk file uploads. They share the same downstream processing (Step Functions → Comprehend → Merge), so there's no code duplication."

**Q: Why serverless instead of EC2?**
> "Serverless eliminates operational overhead—no OS patches, no capacity planning, no server monitoring. It auto-scales from zero to thousands of concurrent executions. For a data pipeline with variable traffic, pay-per-use is more cost-effective than always-on EC2 instances."

### Technical Deep-Dives

**Q: How do you handle failures?**
> "Multiple layers: 1) Kinesis retries failed Lambda batches 3 times. 2) Step Functions has retry with exponential backoff. 3) After exhausting retries, failed messages go to SQS DLQs. 4) CloudWatch alarms trigger when DLQ has messages. 5) I can inspect and replay failed records."

**Q: How do you ensure exactly-once processing?**
> "I don't guarantee exactly-once—I guarantee idempotent processing. The ETL Lambda uses Kinesis sequence numbers as S3 filenames, so retries overwrite the same file. The Merge Lambda uses recordId as the DynamoDB partition key, so duplicates just overwrite. The end result is the same as exactly-once."

**Q: How do you optimize Athena costs?**
> "Three techniques: 1) Partition pruning—WHERE clauses on year/month/day skip irrelevant data. 2) Curated layer—the Merge Lambda pre-computes sentiment counts, so the pie chart doesn't need Athena. 3) For production, I'd convert JSON to Parquet for columnar storage benefits."

### Scenario Questions

**Q: The dashboard is slow. How do you debug?**
> "First, check which data source is slow. The dashboard uses three: Curated S3 (~100ms), DynamoDB (~50ms), Athena (~3s). If Athena is slow, check if partition pruning is working. If DynamoDB is slow, check the GSI. Check CloudWatch metrics for throttling. Use X-Ray for distributed tracing."

**Q: A new field needs to be added to the data. What changes?**
> "1) Update the Merge Lambda to include the new field. 2) Deploy to dev. 3) Run the Glue Crawler to update the table schema (UPDATE_IN_DATABASE policy adds new columns). 4) Update the dashboard to display the new field. No manual DDL needed—Glue handles schema evolution."

**Q: How would you scale this to 10x traffic?**
> "Kinesis: Add shards (currently 1, can scale to 100+). Lambda: Auto-scales, but increase memory if CPU-bound. DynamoDB: Already on-demand, auto-scales. Step Functions: Check state transition limits. Athena: No changes needed, but consider Parquet for faster queries. Main concern: Comprehend API limits—would need to request limit increases."

### Cost Questions

**Q: What's the most expensive component?**
> "Kinesis, because of shard-hour billing (~$0.015/hour even when idle). For low traffic, SQS might be cheaper. At high traffic, Comprehend costs can grow quickly—I'd batch texts to maximize the 5KB limit per request."

**Q: How would you reduce costs by 50%?**
> "1) Convert to Parquet (reduce Athena scan costs). 2) Use SQS instead of Kinesis if ordering isn't needed. 3) Increase Lambda batch sizes (fewer invocations). 4) Move DynamoDB to provisioned capacity with reserved capacity. 5) Extend CloudWatch retention but export to S3 Glacier."

---

## Key Takeaways

### Remember These Patterns

1. **Dual Storage Strategy**: DynamoDB for hot data (fast, expensive), S3 for cold data (slow, cheap)
2. **Event-Driven Architecture**: Loose coupling via EventBridge, Kinesis, Step Functions
3. **Least-Privilege IAM**: Every role has exactly the permissions it needs
4. **Idempotent Processing**: Use deterministic IDs (sequence numbers) to prevent duplicates
5. **Three-Tier Data Lake**: Raw (bronze), Processed (silver), Curated (gold)
6. **Cost Optimization**: Lifecycle policies, TTL, partition pruning, pre-computed aggregations

### Common Pitfalls to Avoid

1. **Infinite Loops**: Always filter EventBridge rules to specific prefixes
2. **Hot Partitions**: Use high-cardinality partition keys in DynamoDB
3. **Expensive Queries**: Always use partition pruning with Athena
4. **Permission Creep**: Start with zero permissions, add only what's needed
5. **Timeout Traps**: Set Lambda timeouts lower than the queue visibility timeout

### Architecture Principles

1. **Serverless First**: Use managed services, avoid EC2
2. **Event-Driven**: Decouple components with events
3. **Fail Gracefully**: DLQs, retries, alarms
4. **Cost-Aware**: Lifecycle policies, TTL, right-sizing
5. **Security by Default**: Encryption, least-privilege, no public access

---

*This document should be reviewed alongside `explained.md` for the full project walkthrough and `roadmap.md` for implementation phases.*
