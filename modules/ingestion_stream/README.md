# Streaming Ingestion Module

## What It Does

Creates a real-time data ingestion pipeline using AWS API Gateway HTTP API and Amazon Kinesis Data Streams. Clients send JSON payloads to an HTTP endpoint, which directly writes to a Kinesis stream without Lambda proxy overhead.

**Data Flow**: Client → API Gateway (POST /ingest) → Kinesis Stream → Lambda ETL → S3 `raw/`

---

## Why This Architecture?

**HTTP API vs REST API**:
- 70% cheaper than REST API for this use case
- Simpler configuration, fewer features we don't need
- Perfect for modern API-first architectures

**Direct Integration (No Lambda Proxy)**:
- Lower latency (no Lambda cold starts during ingestion)
- Lower cost (no Lambda invocations for writes)
- Kinesis handles buffering and traffic spikes

**Kinesis as Buffer**:
- Decouples ingestion from processing
- Absorbs traffic within shard capacity (1 MB/s, 1k records/s per shard); switch to on-demand for unpredictable bursts
- Enables replay and multi-consumer patterns

---

## Resources Created

### Core Resources
- **Kinesis Data Stream**: Receives and buffers real-time data
- **API Gateway HTTP API**: Public HTTP endpoint for data ingestion
- **API Gateway Stage**: `$default` stage with auto-deploy enabled
- **API Gateway Route**: `POST /ingest` route
- **API Gateway Integration**: Direct integration to Kinesis `PutRecord`

### IAM Resources
- **IAM Role**: Allows API Gateway to call Kinesis
- **IAM Policy**: Grants `kinesis:PutRecord` permission (least privilege)

### Observability Resources
- **CloudWatch Log Group**: Stores API Gateway access logs (optional)

---

## Usage Example

```hcl
module "ingestion_stream" {
  source = "../../modules/ingestion_stream"

  environment  = "dev"
  project_name = "ai-dp"
  aws_region   = "us-west-2"

  # Data lake integration (ETL Lambda writes validated records to raw/)
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn

  # Kinesis configuration (provisioned 1-shard — cost-optimized for steady low traffic)
  kinesis_stream_mode     = "PROVISIONED" # or "ON_DEMAND" for bursty/load-test traffic
  kinesis_shard_count     = 1             # 1 shard = 1 MB/s write capacity
  kinesis_retention_hours = 24            # Increase for a longer replay window
  kinesis_encryption_type = "KMS"         # AWS-managed key; "NONE" to disable

  # API Gateway configuration
  enable_api_gateway_logging     = true
  api_gateway_log_retention_days = 7
  enable_cors                    = true
  cors_allow_origins             = ["*"] # Restrict in production

  tags = {
    Component = "Ingestion"
    DataFlow  = "Streaming"
  }
}
```

---

## Key Variables

### Required Variables
- **`environment`**: Environment name (dev/stg/prod)
- **`project_name`**: Project name for resource naming
- **`aws_region`**: AWS region for resources

### Kinesis Configuration
- **`kinesis_stream_mode`**: Capacity mode (default: "PROVISIONED")
  - "PROVISIONED": ~$11/mo for 1 shard, best for steady low-volume traffic
  - "ON_DEMAND": flat ~$29/mo, auto-scales for bursty/unpredictable traffic
- **`kinesis_shard_count`**: Shards for PROVISIONED mode (default: 1, 1 shard = 1 MB/s write). Ignored when ON_DEMAND.
- **`kinesis_retention_hours`**: Data retention (default: 24, max: 8760)
  - 24 hours: Good for dev, low cost
  - 168 hours (7 days): Good for production debugging

- **`kinesis_encryption_type`**: Encryption type (default: "NONE")
  - "NONE": Free, AWS manages keys
  - "KMS": Additional cost, customer-managed keys

### API Gateway Configuration
- **`enable_api_gateway_logging`**: Enable CloudWatch logs (default: true)
- **`api_gateway_log_retention_days`**: Log retention (default: 7 days)
- **`enable_cors`**: Enable CORS (default: true)
- **`cors_allow_origins`**: Allowed origins (default: ["*"])

---

## Outputs

### For Testing
- **`api_gateway_invoke_url`**: Full API endpoint URL (e.g., `https://abc123.execute-api.us-west-2.amazonaws.com/ingest`)

### For Lambda Integration
- **`kinesis_stream_name`**: Stream name for Lambda event source mapping
- **`kinesis_stream_arn`**: Stream ARN for IAM policies

### For Monitoring
- **`api_gateway_id`**: API Gateway ID for CloudWatch metrics
- **`kinesis_stream_id`**: Kinesis stream ID

---

## Testing the API

### Quick Test with PowerShell

```powershell
# Get the API URL from Terraform outputs
$url = terraform -chdir=envs/dev output -raw api_gateway_invoke_url

# Send test request
Invoke-RestMethod -Uri $url -Method Post `
  -Headers @{
    "Content-Type" = "application/json"
    "X-Partition-Key" = "test-partition"
  } `
  -Body '{"event_type":"test","timestamp":"2025-01-24T12:00:00Z","data":{"test":true}}'
```

### Expected Response (Success)

```json
{
  "SequenceNumber": "49668384628563227189446682340889554666034754153915351042",
  "ShardId": "shardId-000000000000"
}
```

### Test with cURL

```bash
curl -X POST https://{api-id}.execute-api.us-west-2.amazonaws.com/ingest \
  -H "Content-Type: application/json" \
  -H "X-Partition-Key: test-partition" \
  -d '{
    "event_type": "test",
    "timestamp": "2025-01-24T12:00:00Z",
    "data": {
      "test": true,
      "message": "Hello from Kinesis"
    }
  }'
```

### Verify in AWS Console

**Kinesis Console**:
1. Navigate to: Kinesis → Data Streams → `{project}-{env}-ingestion-stream`
2. Click "Monitoring" tab
3. Check "PutRecord - sum" metric (should show activity)
4. Check "Incoming data - sum" metric (should show data throughput)

**API Gateway Console**:
1. Navigate to: API Gateway → APIs → `{project}-{env}-ingestion-api`
2. Click "Stages" → "$default"
3. Check CloudWatch logs (if logging enabled)

---

## EventBridge Batch Ingestion Detection

### What It Does

Detects batch file uploads to the data lake `raw/` layer for orchestrated processing. When files are uploaded directly to S3 (bypassing the streaming API path), EventBridge triggers processing workflows.

**Data Flow**: S3 upload to `raw/` → EventBridge rule → Step Functions orchestration

### Why EventBridge vs S3 Notifications?

**Centralized Event Routing**:
- Easier to add multiple targets later without reconfiguring S3 bucket
- Can route to Step Functions, Lambda, SNS, SQS from one rule
- Better for evolving architectures

**Advanced Filtering**:
- Can filter by bucket + prefix in a single rule
- Complex event patterns (multiple conditions)
- No need to manage multiple S3 notification configurations

**Native AWS Service Integration**:
- Direct integration with Step Functions (no Lambda glue code)
- Built-in retry and error handling
- CloudWatch metrics included automatically

**Better for Portfolio Projects**:
- Demonstrates modern AWS event-driven architecture
- Shows understanding of decoupled systems

### Why Filter to raw/ Prefix Only?

**Prevents Infinite Loops**:
- Processing pipeline writes to `processed/` layer
- Without filtering, processed writes would re-trigger the pipeline
- Could cause exponential cost growth and endless loops

**Clear Layer Separation**:
- `raw/` = ingestion trigger point (batch uploads)
- `processed/` = output from AI enrichment (no trigger)
- `curated/` = analytics-ready (no trigger)

**Streaming vs Batch Paths**:
- Streaming data uses Kinesis path (no EventBridge)
- Batch uploads trigger EventBridge → Step Functions
- Two independent ingestion paths for different use cases

### Event Pattern Breakdown

```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {
      "name": ["ai-dp-data-lake-dev"]
    },
    "object": {
      "key": [{
        "prefix": "raw/"
      }]
    }
  }
}
```

**What Triggers the Rule**:
- ✅ `s3://bucket/raw/data.json` → Triggers
- ✅ `s3://bucket/raw/subfolder/data.csv` → Triggers
- ❌ `s3://bucket/processed/data.json` → Ignored
- ❌ `s3://bucket/curated/data.json` → Ignored
- ❌ `s3://other-bucket/raw/data.json` → Ignored

### Cost Awareness

**EventBridge Pricing**:
- $1.00 per million events
- At typical batch upload volumes (dozens per day): ~$0.01/month

**CloudWatch Metrics**:
- Free for AWS service metrics (includes EventBridge rule invocations)

### Testing the EventBridge Rule

**Test 1: Upload to raw/ (should trigger)**:
```powershell
echo '{"test": "data"}' > test.json
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json
```

**Verify in AWS Console**:
1. CloudWatch → Metrics → EventBridge → By Rule Name
2. Find rule: `ai-dp-dev-s3-batch-ingestion`
3. Check "Invocations" metric → Should show 1 invocation ✅

**Test 2 & 3: Upload to processed/ and curated/ (should NOT trigger)**:
```powershell
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/processed/test.json
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/curated/test.json
# Invocations metric should NOT increase ✅
```

---

## Capacity Planning

This stream runs in **provisioned mode with 1 shard** by default. Each shard provides 1 MB/s (1,000 records/s) of write capacity — comfortably above this workload's steady, low-volume traffic — at the lowest cost. For unpredictable or spiky workloads (e.g. load tests), set `kinesis_stream_mode = "ON_DEMAND"` to let Kinesis auto-scale without managing shards, at a higher flat hourly rate.

### Cost Breakdown (us-west-2, 2026)

**Kinesis — Provisioned (default, 1 shard)**:
- Shard hour: ~$0.015 per hour (~$11/month for 1 shard)
- PUT payload units: $0.014 per million 25 KB units (negligible at low volume)
- Extended retention: $0.02 per shard-hour for > 24 hours

**Kinesis — On-Demand (optional, for bursts)**:
- Stream hour: ~$0.04 per hour (**~$29/month flat, regardless of throughput**)
- Data written/read: per-GB charges on top of the stream hour

**API Gateway HTTP API**:
- First 300M requests: $1.00 per million
- Next 700M requests: $0.90 per million
- Data transfer: Standard AWS rates

**CloudWatch Logs** (if enabled):
- Ingestion: $0.50 per GB
- Storage: $0.03 per GB/month
- Retention: 7 days = minimal cost for dev

---

## Security Considerations

### Current Security (Dev)

✅ **HTTPS Only**: API Gateway enforces TLS in transit
✅ **IAM Least Privilege**: API Gateway role only has `kinesis:PutRecord` / `PutRecords` on this one stream
✅ **Throttling**: 1 request/s, burst 5 (caps cost from abuse; doesn't stop it)
✅ **No Hardcoded Secrets**: All credentials managed by IAM
⚠️ **CORS Wide Open**: `cors_allow_origins = ["*"]` (dev only)
⚠️ **No Authentication**: Public endpoint (anyone can POST)

### Production Hardening

For production, consider adding:

**Authentication**:
- Lambda authorizer (JWT validation)
- IAM authentication (for internal services)

**CORS Restrictions**:
```hcl
cors_allow_origins = ["https://app.example.com"]
```

**Encryption**:
```hcl
kinesis_encryption_type = "KMS"
kinesis_kms_key_id      = aws_kms_key.kinesis.id
```

**Request Validation**:
- Add Lambda authorizer to validate request schema

---

## Troubleshooting

### Issue: API returns 403 Forbidden

**Cause**: IAM role doesn't have permission to write to Kinesis
**Check**: Verify IAM role has `kinesis:PutRecord` on stream ARN
**Fix**: Run `terraform plan` to check IAM policy matches stream ARN

### Issue: API returns 500 Internal Server Error

**Cause**: Missing `X-Partition-Key` header
**Check**: Request includes `X-Partition-Key` header
**Fix**: Add header: `-H "X-Partition-Key: your-key"`

### Issue: Data not appearing in Kinesis

**Cause**: Wrong stream name in integration
**Check**: API Gateway integration has correct stream name
**Fix**: Verify in console: API Gateway → Integrations → Check `StreamName` parameter

### Issue: High API Gateway latency

**Cause**: Kinesis throttling due to shard capacity limits.
**Check**: Kinesis CloudWatch metric `WriteProvisionedThroughputExceeded`.
**Fix**: In provisioned mode each shard handles 1 MB/s (1k records/s). Add shards via `kinesis_shard_count` or improve the partition-key strategy to spread load evenly. For sustained unpredictable spikes, switch to `kinesis_stream_mode = "ON_DEMAND"`.

---

## Pipeline Integration

This module is the entry point of the streaming path and connects to the rest of the deployed pipeline:

1. **ETL Lambda** (`lambdas/etl/`) — consumes the Kinesis stream via an event source mapping, validates and normalizes records, and writes them to the S3 `raw/` layer. X-Ray active tracing is enabled for per-invocation latency visibility.
2. **Dead Letter Queue** — an SQS DLQ (14-day retention) captures failed ETL invocations, with a CloudWatch alarm on DLQ depth.
3. **EventBridge → Step Functions** — object-created events on `raw/` trigger the Step Functions orchestrator for AI enrichment (the EventBridge rule defined in this module).

---

## References

- [AWS API Gateway HTTP APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)
- [AWS Kinesis Data Streams](https://docs.aws.amazon.com/streams/latest/dev/introduction.html)
- [API Gateway Service Integrations](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-aws-services.html)
- [Terraform aws_apigatewayv2_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api)
- [Terraform aws_kinesis_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_stream)
