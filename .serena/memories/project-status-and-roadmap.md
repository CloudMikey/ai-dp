# AI-DP Project Status & Roadmap

**Last Updated:** 2025-10-27

## Current Status: 30% Complete (3 of 10 Phases)

### ✅ Completed Phases

#### Phase 0: Bootstrap Infrastructure
- S3 state bucket: `tf-state-aidp` (us-west-1)
- Terraform 1.13.0 with native S3 locking (`use_lockfile = true`)
- All environments initialized (dev, stg, prod)

#### Phase 1: Data Lake Foundation
**Bucket:** `ai-dp-data-lake-dev-us-west-1`

**Achievements:**
- Three-layer S3 architecture (raw/processed/curated)
- Lifecycle policies with dynamic blocks (avoid empty rule errors)
- Security: SSE-AES256, versioning, public access blocked, TLS enforced
- EventBridge notifications enabled (`aws_s3_bucket_notification.eventbridge`)
- Provider `default_tags` pattern (no tag conflicts)

#### Phase 2: Streaming Ingestion Path
**API:** `https://57cnx9jpje.execute-api.us-west-1.amazonaws.com//ingest`

**Components:**
- Kinesis: `ai-dp-dev-ingestion-stream` (1 shard, 24h retention)
- API Gateway HTTP API → Kinesis (direct integration)
- Lambda ETL: `ai-dp-dev-etl` (Python 3.11, 256MB, 60s)
- Event source mapping (batch=100, retry=3)
- SQS DLQ: `ai-dp-dev-etl-dlq` (14-day retention)

**Testing:**
- ✅ End-to-end: API → Kinesis → Lambda → S3 raw/
- ✅ S3 partitioning: `raw/year=2025/month=10/day=27/`
- ✅ DLQ error handling verified

### 🔄 Next Phase

#### Phase 3: Batch Ingestion Path (EventBridge Rule)
**Goal:** Detect S3 uploads to raw/ layer

**Tasks:**
1. Add EventBridge rule to `ingestion_stream` module
2. Event pattern: S3 Object Created in raw/ prefix
3. CloudWatch metrics for monitoring
4. Test upload detection (no target yet)

**Note:** EventBridge targets added in Phase 4 (Step Functions)

### 📋 Remaining Phases

- Phase 4: Step Functions Placeholder & EventBridge Wiring
- Phase 5: DynamoDB Hot Store
- Phase 6: AI Enrichment (Comprehend)
- Phase 7: Merge Lambda & Complete Orchestration
- Phase 8: Analytics (Glue, Athena, Dashboard)
- Phase 9: Production Hardening
- Phase 10: CI/CD Pipeline

## Key Infrastructure Outputs

```hcl
data_lake_bucket_name = "ai-dp-data-lake-dev-us-west-1"
kinesis_stream_name = "ai-dp-dev-ingestion-stream"
api_gateway_invoke_url = "https://57cnx9jpje.execute-api.us-west-1.amazonaws.com//ingest"
```

## Module Structure

```
modules/
├── data_lake/           # Phase 1 - S3 + EventBridge notifications
└── ingestion_stream/    # Phase 2 - API Gateway + Kinesis + Lambda ETL
```

## Development Commands

```powershell
# Terraform workflow
terraform -chdir=envs/dev fmt
terraform -chdir=envs/dev validate
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev apply

# Test streaming ingestion
curl -X POST "https://57cnx9jpje.execute-api.us-west-1.amazonaws.com//ingest" `
  -H "Content-Type: application/json" `
  -H "X-Partition-Key: test-key" `
  -d '{"event_type":"test","event_timestamp":"2025-10-27T20:00:00Z"}'

# Verify S3 data
aws s3 ls s3://ai-dp-data-lake-dev-us-west-1/raw/ --recursive --region us-west-1

# Check DLQ
aws sqs get-queue-attributes --queue-url https://sqs.us-west-1.amazonaws.com/061039801477/ai-dp-dev-etl-dlq --attribute-names ApproximateNumberOfMessages --region us-west-1
```

## Important Lessons Learned

1. **Tag Conflicts:** Use provider `default_tags` for global tags; modules add resource-specific tags only
2. **Lifecycle Rules:** Use dynamic blocks with `for_each` to avoid empty rule errors
3. **IAM Least Privilege:** Scope S3 permissions to specific prefixes (e.g., `raw/*`)
4. **AWS Managed Policies:** Using AWS managed policy ARNs (e.g., `arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole`) is standard practice, not bad hardcoding
