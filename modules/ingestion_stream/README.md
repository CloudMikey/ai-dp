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
- **`kinesis_shard_count`**: Number of shards (default: 1)
  - 1 shard = 1 MB/sec write, 2 MB/sec read
  - Scale based on throughput: 10 req/sec @ 1KB = 0.01 MB/sec (well within 1 shard)

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

## Capacity Planning

### Shard Sizing Guide

| Expected Throughput | Shard Count | Cost (approx) |
|---------------------|-------------|---------------|
| < 1 MB/sec          | 1           | ~$0.015/hr    |
| 1-2 MB/sec          | 2           | ~$0.030/hr    |
| 2-5 MB/sec          | 3-5         | ~$0.045-0.075/hr |

**Example Calculations**:
- 10 requests/sec × 1 KB payload = 10 KB/sec = 0.01 MB/sec → **1 shard**
- 100 requests/sec × 5 KB payload = 500 KB/sec = 0.5 MB/sec → **1 shard**
- 1000 requests/sec × 2 KB payload = 2000 KB/sec = 2 MB/sec → **2 shards**

### Cost Breakdown (us-west-1, as of 2025)

**Kinesis**:
- Shard Hour: $0.015/hour ($10.80/month per shard)
- PUT Payload Unit (25KB): $0.014 per million units
- Extended Retention: $0.02 per shard-hour for > 24 hours

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

**Cause**: Kinesis throttling or shard limit reached
**Check**: Kinesis CloudWatch metrics for `WriteProvisionedThroughputExceeded`
**Fix**: Increase `kinesis_shard_count` or implement client-side retry

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
