# Streaming Ingestion Module

## What It Does

Creates a real-time data ingestion pipeline using AWS API Gateway HTTP API and Amazon Kinesis Data Streams. Clients send JSON payloads to an HTTP endpoint, which directly writes to a Kinesis stream without Lambda proxy overhead.

**Data Flow**: Client → API Gateway (POST /ingest) → Kinesis Stream → (Future: Lambda ETL → S3)

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
- Handles traffic spikes (1 MB/sec per shard)
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
  aws_region   = "us-west-1"

  # Kinesis configuration (1 shard = 1 MB/sec write capacity)
  kinesis_shard_count     = 1  # Scale to 2-5 for production
  kinesis_retention_hours = 24 # Increase for longer replay window
  kinesis_encryption_type = "NONE" # Use "KMS" in production

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
- **`api_gateway_invoke_url`**: Full API endpoint URL (e.g., `https://abc123.execute-api.us-west-1.amazonaws.com/ingest`)

### For Lambda Integration (Phase 2)
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
curl -X POST https://{api-id}.execute-api.us-west-1.amazonaws.com/ingest \
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

## EventBridge Batch Ingestion Detection (Phase 3)

### What It Does

Detects batch file uploads to the data lake `raw/` layer for orchestrated processing. When files are uploaded directly to S3 (bypassing the streaming API path), EventBridge triggers processing workflows.

**Data Flow**: S3 upload to `raw/` → EventBridge rule → (Phase 4: Step Functions orchestration)

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
- Easier to explain in interviews than S3 notifications
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
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-1/raw/test.json
```

**Verify in AWS Console**:
1. CloudWatch → Metrics → EventBridge → By Rule Name
2. Find rule: `ai-dp-dev-s3-batch-ingestion`
3. Check "Invocations" metric → Should show 1 invocation ✅

**Test 2 & 3: Upload to processed/ and curated/ (should NOT trigger)**:
```powershell
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-1/processed/test.json
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-1/curated/test.json
# Invocations metric should NOT increase ✅
```

### Interview Talking Points

**Q: Why EventBridge instead of S3 bucket notifications?**
> "EventBridge provides centralized event routing and advanced filtering. With S3 notifications, you configure targets directly on the bucket - if you want to add another consumer later, you have to reconfigure the bucket. With EventBridge, I can add multiple targets to the same event rule without touching the S3 bucket. It's more flexible for evolving architectures."

**Q: How does the event pattern filtering work?**
> "The event pattern uses JSON to define three filters: source must be aws.s3, detail-type must be Object Created, and the object key must start with 'raw/'. This ensures only new uploads to the raw layer trigger processing. Uploads to processed or curated layers are ignored, preventing infinite loops."

**Q: What happens if the rule fails to invoke a target?**
> "In Phase 4, we'll add a dead letter queue for failed invocations. EventBridge has built-in retry logic - it retries failed deliveries with exponential backoff. If all retries fail, the event goes to the DLQ where we can replay it or investigate the failure."

---

## Capacity Planning

With **on-demand billing**, you no longer need to provision or manage shards. Kinesis automatically scales capacity based on your workload. This model is ideal for unpredictable or spiky workloads, as it eliminates the need for manual capacity planning.

### Cost Breakdown (us-west-1, as of 2025 - On-Demand)

**Kinesis**:
- Per-stream hour: ~$0.04 per hour
- Data written: ~$0.20 per GB
- Data read: ~$0.02 per GB
- Extended Retention: $0.02 per hour for > 24 hours (billed per shard)

**API Gateway HTTP API**:
- First 300M requests: $1.00 per million
- Next 700M requests: $0.90 per million
- Data transfer: Standard AWS rates

**CloudWatch Logs** (if enabled):
- Ingestion: $0.50 per GB
- Storage: $0.03 per GB/month
- Retention: 7 days = minimal cost for dev

---

## Interview Talking Points

### Architecture Decisions

**Q: Why HTTP API over REST API?**
> "I chose HTTP API because it's AWS's modern API solution - 70% cheaper and simpler for this use case. REST API has features like API keys and request validation that we don't need. HTTP API is perfect for direct AWS service integrations."

**Q: Why direct integration instead of Lambda proxy?**
> "Direct integration eliminates Lambda cold starts during ingestion, reducing latency from 100-500ms to under 50ms. It's also cheaper since we're not paying for Lambda invocations just to write to Kinesis. Kinesis handles the buffering, so we don't need Lambda for that."

**Q: How does this handle traffic spikes?**
> "Kinesis acts as a buffer between ingestion and processing. Each shard can handle 1 MB/sec of writes, and API Gateway can scale to thousands of requests per second. If we get a spike, Kinesis stores the data and our Lambda consumers process it at their own pace."

**Q: What happens if a write fails?**
> "API Gateway returns the error to the client immediately. The client can implement retry logic with exponential backoff. We also have CloudWatch metrics and logs to track failed requests and diagnose issues."

### Scaling Considerations

**Q: How would you scale this for production?**
> "I'd increase shard count based on expected throughput. For example, if we expect 5 MB/sec during peak hours, I'd provision 6 shards for headroom. I'd also enable KMS encryption for data at rest and restrict CORS to specific domains."

**Q: How do you monitor this?**
> "CloudWatch metrics for Kinesis (PutRecord success rate, incoming data) and API Gateway (4xx/5xx errors, latency). I'd set up alarms for high error rates or when Kinesis utilization exceeds 80%. For production, I'd add X-Ray tracing to diagnose latency issues."

### Cost Optimization

**Q: How did you optimize costs?**
> "Started with 1 shard for dev since our throughput is low. Used NONE encryption instead of KMS to save on KMS costs. Set 7-day log retention instead of indefinite. Used HTTP API instead of REST API for 70% cost savings. In production, I'd use Reserved Capacity for predictable shard usage."

---

## Security Considerations

### Current Security (Dev)

✅ **HTTPS Only**: API Gateway enforces TLS in transit
✅ **IAM Least Privilege**: API Gateway role only has `kinesis:PutRecord`
✅ **No Hardcoded Secrets**: All credentials managed by IAM
⚠️ **CORS Wide Open**: `cors_allow_origins = ["*"]` (dev only)
⚠️ **No Authentication**: Public endpoint (anyone can POST)

### Production Hardening

For production, consider adding:

**Authentication**:
- Lambda authorizer (JWT validation)
- IAM authentication (for internal services)
- API key requirement (for partner integrations)

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
- Implement rate limiting (API Gateway throttling)

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

**Cause**: Kinesis throttling due to stream capacity limits.
**Check**: Kinesis CloudWatch metrics for `WriteThroughputExceeded` (on-demand mode metric).
**Fix**: Although Kinesis scales automatically in on-demand mode, there are still account and stream-level limits. If throttling occurs, you may need to request a service quota increase or analyze your partition key strategy to ensure even distribution.

---

## Next Steps (Phase 2)

After completing this module:

1. **Create Lambda ETL Function** (`lambdas/etl/`)
   - Consume from Kinesis stream
   - Validate and normalize data
   - Write to S3 `raw/` layer

2. **Add Lambda Event Source Mapping**
   - Connect Lambda to Kinesis stream
   - Configure batch size and retry behavior

3. **Add Dead Letter Queue (DLQ)**
   - SQS queue for failed Lambda invocations
   - CloudWatch alarm on DLQ depth

4. **Enable EventBridge Notifications**
   - S3 EventBridge notifications for batch uploads
   - Triggers Step Functions orchestration

---

## References

- [AWS API Gateway HTTP APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)
- [AWS Kinesis Data Streams](https://docs.aws.amazon.com/streams/latest/dev/introduction.html)
- [API Gateway Service Integrations](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-aws-services.html)
- [Terraform aws_apigatewayv2_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api)
- [Terraform aws_kinesis_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_stream)
