# Orchestration Module

Creates the Merge Lambda function that combines AI enrichment results and implements the **dual storage strategy** (S3 processed layer + DynamoDB hot store).

## Purpose

The orchestration module completes the data pipeline by:
- **Merging AI outputs**: Combines sentiment analysis and entity extraction results from Amazon Comprehend
- **Dual-write pattern**: Writes enriched data to both S3 `processed/` (historical analytics) and DynamoDB (real-time queries)
- **Error handling**: SQS Dead Letter Queue captures failed invocations for debugging and replay
- **Metadata enrichment**: Adds processing timestamps, Lambda version info, and record versioning

## Architecture

### Data Flow

```
Step Functions (AI Enrichment Complete)
  ↓
Merge Lambda receives:
  - recordId (S3 object key)
  - sentiment (POSITIVE/NEGATIVE/NEUTRAL/MIXED)
  - sentimentScores (confidence percentages)
  - entities (people, places, organizations)
  ↓
Lambda reads original record from S3 raw/
  ↓
Merges AI results with original data
  ↓
Dual Write:
  1. S3 processed/ with date partitioning
  2. DynamoDB with 30-day TTL
  ↓
Returns success with both storage locations
```

### Merge Lambda Responsibilities

1. **Extract original data**: Reads raw record from S3 based on `recordId`
2. **Combine outputs**: Merges original data + sentiment + entities into single object
3. **Enrich metadata**: Adds `processed_at`, `lambda_version`, `record_version`
4. **Date partition**: Writes to S3 `processed/year=YYYY/month=MM/day=DD/`
5. **Set TTL**: Calculates `expiresAt` for DynamoDB auto-deletion (30 days default)
6. **Error handling**: Sends failed records to SQS DLQ after 3 retries

## Features

- **Dual Storage Strategy**: S3 for cost-effective historical queries, DynamoDB for fast real-time access
- **Automatic Retries**: Lambda retries transient failures 3 times before sending to DLQ
- **Dead Letter Queue**: 14-day retention for debugging and replay
- **CloudWatch Logs**: All invocations logged for debugging (7-day retention default)
- **Least-Privilege IAM**: Scoped permissions (read `raw/*`, write `processed/*`, PutItem to DynamoDB)
- **Environment Variables**: Configurable bucket names, prefixes, TTL, log levels

## Usage

```hcl
module "orchestration" {
  source = "../../modules/orchestration"

  environment  = "dev"
  project_name = "ai-dp"

  # Data Lake dependencies (from data_lake module)
  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn

  # DynamoDB dependencies (from hot_store module)
  dynamodb_table_name = module.hot_store.table_name
  dynamodb_table_arn  = module.hot_store.table_arn

  # Optional: Override defaults
  processed_prefix   = "processed/"
  ttl_days           = 30
  log_level          = "INFO"
  log_retention_days = 7

  tags = {
    Component = "Orchestration"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name (dev, stg, prod) | `string` | n/a | yes |
| project_name | Project name for resource naming | `string` | `"ai-dp"` | no |
| data_lake_bucket_name | S3 bucket name (from data_lake module) | `string` | n/a | yes |
| data_lake_bucket_arn | S3 bucket ARN for IAM policies | `string` | n/a | yes |
| dynamodb_table_name | DynamoDB table name (from hot_store module) | `string` | n/a | yes |
| dynamodb_table_arn | DynamoDB table ARN for IAM policies | `string` | n/a | yes |
| processed_prefix | S3 prefix for processed data | `string` | `"processed/"` | no |
| ttl_days | TTL in days for DynamoDB records | `number` | `30` | no |
| log_level | Lambda logging level (INFO/DEBUG/ERROR) | `string` | `"INFO"` | no |
| log_retention_days | CloudWatch Logs retention days | `number` | `7` | no |
| tags | Additional resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| lambda_function_arn | ARN of Merge Lambda (used by Step Functions) |
| lambda_function_name | Lambda function name |
| lambda_role_arn | IAM role ARN for Lambda execution |
| dlq_url | SQS Dead Letter Queue URL (for monitoring) |
| dlq_arn | SQS Dead Letter Queue ARN |
| cloudwatch_log_group_name | CloudWatch Log Group name |

## Lambda Function Details

**Runtime**: Python 3.11
**Memory**: 256 MB
**Timeout**: 60 seconds
**Handler**: `app.lambda_handler`

**Environment Variables**:
- `DATA_LAKE_BUCKET`: S3 bucket name
- `PROCESSED_PREFIX`: S3 prefix for processed data
- `DYNAMODB_TABLE`: DynamoDB table name
- `TTL_DAYS`: Days before DynamoDB record expires
- `LOG_LEVEL`: Logging verbosity (INFO/DEBUG/ERROR)

**Lambda Code Location**: [`lambdas/merge/app.py`](../../lambdas/merge/app.py)

## IAM Permissions (Least-Privilege)

### S3 Read (raw layer only)
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject"],
  "Resource": "arn:aws:s3:::bucket-name/raw/*"
}
```

### S3 Write (processed layer only)
```json
{
  "Effect": "Allow",
  "Action": ["s3:PutObject"],
  "Resource": "arn:aws:s3:::bucket-name/processed/*"
}
```

### DynamoDB Write (single table)
```json
{
  "Effect": "Allow",
  "Action": ["dynamodb:PutItem"],
  "Resource": "arn:aws:dynamodb:region:account:table/ai-dp-dev-enriched-data"
}
```

### SQS (DLQ only)
```json
{
  "Effect": "Allow",
  "Action": ["sqs:SendMessage"],
  "Resource": "arn:aws:sqs:region:account:ai-dp-dev-merge-dlq"
}
```

### CloudWatch Logs
```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "arn:aws:logs:region:account:log-group:/aws/lambda/*"
}
```

## S3 Processed Layer Structure

The Lambda writes enriched data with date partitioning for efficient Athena queries:

```
s3://ai-dp-data-lake-dev-us-west-2/processed/
  year=2025/
    month=12/
      day=07/
        enriched-record-001.json
        enriched-record-002.json
    month=11/
      day=30/
        enriched-record-003.json
```

**Why Date Partitioning?**
- Athena queries scan only relevant partitions (faster + cheaper)
- Example: `WHERE year=2025 AND month=12` only scans December data
- Lifecycle policies can target specific date ranges

## DynamoDB Record Structure

```json
{
  "recordId": "raw/year=2025/month=12/day=07/record-123.json",
  "timestamp": 1733590800000,
  "recordType": "text",
  "originalText": "I love this product! It's amazing!",
  "sentiment": "POSITIVE",
  "sentimentScore": 0.9876,
  "entities": [
    {
      "Text": "product",
      "Type": "COMMERCIAL_ITEM",
      "Score": 0.95
    }
  ],
  "rawDataLocation": "s3://bucket/raw/year=2025/month=12/day=07/record-123.json",
  "processedDataLocation": "s3://bucket/processed/year=2025/month=12/day=07/enriched-record-123.json",
  "processedAt": "2025-12-07T10:30:00Z",
  "lambdaVersion": "$LATEST",
  "recordVersion": 1,
  "expiresAt": 1736182800
}
```

**Key Fields**:
- `expiresAt`: Unix epoch (seconds) for TTL auto-deletion (30 days default)
- `timestamp`: Unix epoch (milliseconds) for GSI time-based queries
- `recordType`: Partition key for GSI (`text`, `image`, etc.)

## Error Handling

### Retry Strategy

Lambda automatically retries on transient failures:
1. **1st attempt**: Immediate execution
2. **2nd attempt**: After 2 seconds (if transient error)
3. **3rd attempt**: After 4 seconds (if transient error)
4. **DLQ**: After 3 failed attempts, message sent to SQS DLQ

**Transient Errors** (retriable):
- `S3.ServiceException`
- `DynamoDB.ProvisionedThroughputExceededException`
- Network timeouts

**Non-Transient Errors** (immediate DLQ):
- Validation errors (missing fields)
- S3 object not found
- Malformed JSON

### Monitoring Failed Invocations

**Check DLQ depth**:
```powershell
aws sqs get-queue-attributes `
  --queue-url https://sqs.us-west-2.amazonaws.com/123456789012/ai-dp-dev-merge-dlq `
  --attribute-names ApproximateNumberOfMessages `
  --region us-west-2
```

**Read DLQ messages**:
```powershell
aws sqs receive-message `
  --queue-url https://sqs.us-west-2.amazonaws.com/123456789012/ai-dp-dev-merge-dlq `
  --max-number-of-messages 10 `
  --region us-west-2
```

**View Lambda errors in CloudWatch**:
```powershell
aws logs filter-log-events `
  --log-group-name /aws/lambda/ai-dp-dev-merge `
  --filter-pattern "ERROR" `
  --region us-west-2
```

## Integration with Step Functions

The Step Functions state machine invokes this Lambda after AI enrichment completes:

```json
{
  "InvokeMergeLambda": {
    "Type": "Task",
    "Resource": "arn:aws:states:::lambda:invoke",
    "Parameters": {
      "FunctionName": "${merge_lambda_arn}",
      "Payload": {
        "recordId.$": "$.detail.object.key",
        "sentiment.$": "$.SentimentResult.Sentiment",
        "sentimentScores.$": "$.SentimentResult.SentimentScore",
        "entities.$": "$.EntitiesResult.Entities"
      }
    },
    "Retry": [
      {
        "ErrorEquals": ["Lambda.ServiceException", "Lambda.TooManyRequestsException"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,
        "BackoffRate": 2.0
      }
    ],
    "Catch": [
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "MergeFailed"
      }
    ],
    "End": true
  }
}
```

**Key Points**:
- Step Functions passes `recordId` (S3 object key), `sentiment`, `sentimentScores`, `entities`
- Retry strategy: 3 attempts with exponential backoff (2s, 4s, 8s)
- Errors caught and sent to `MergeFailed` state (CloudWatch alarm notification)

## Testing

### End-to-End Test (Streaming Path)

```powershell
# 1. Send event via API Gateway
curl -X POST https://57cnx9jpje.execute-api.us-west-2.amazonaws.com/ingest `
  -H "Content-Type: application/json" `
  -d '{"userId": "user123", "text": "I love this product!"}'

# 2. Check Step Functions execution
aws stepfunctions list-executions `
  --state-machine-arn arn:aws:states:us-west-2:123456789012:stateMachine:ai-dp-dev-orchestrator `
  --region us-west-2

# 3. Verify S3 processed/ write
aws s3 ls s3://ai-dp-data-lake-dev-us-west-2/processed/ --recursive --human-readable

# 4. Verify DynamoDB write
aws dynamodb scan `
  --table-name ai-dp-dev-enriched-data `
  --region us-west-2 `
  --limit 5
```

### End-to-End Test (Batch Path)

```powershell
# 1. Upload file to S3 raw/
echo '{"userId": "user456", "text": "This is terrible!"}' | `
  aws s3 cp - s3://ai-dp-data-lake-dev-us-west-2/raw/test-batch.json

# 2. Check EventBridge triggered Step Functions
aws stepfunctions list-executions `
  --state-machine-arn arn:aws:states:us-west-2:123456789012:stateMachine:ai-dp-dev-orchestrator `
  --region us-west-2

# 3. Verify processed/ write
aws s3 ls s3://ai-dp-data-lake-dev-us-west-2/processed/ --recursive

# 4. Verify DynamoDB write
aws dynamodb query `
  --table-name ai-dp-dev-enriched-data `
  --index-name timestamp-index `
  --key-condition-expression "recordType = :type" `
  --expression-attribute-values '{":type": {"S": "text"}}' `
  --region us-west-2
```

### Lambda Direct Invocation Test

```powershell
# Create test payload
$testPayload = @{
  recordId = "raw/year=2025/month=12/day=07/test.json"
  sentiment = "POSITIVE"
  sentimentScores = @{
    Positive = 0.98
    Negative = 0.01
    Neutral = 0.01
    Mixed = 0.00
  }
  entities = @(
    @{
      Text = "AWS"
      Type = "ORGANIZATION"
      Score = 0.99
    }
  )
} | ConvertTo-Json -Depth 5

# Invoke Lambda
aws lambda invoke `
  --function-name ai-dp-dev-merge `
  --payload $testPayload `
  --region us-west-2 `
  response.json

# Check result
cat response.json
```

## Interview Talking Points

### 1. Why separate orchestration module?
"The orchestration module handles the final step of the pipeline—merging AI results and implementing the dual storage strategy. Separating it from other modules follows single-responsibility principle: each module does one thing well."

### 2. Why dual storage (S3 + DynamoDB)?
"S3 provides cost-effective historical storage for analytics ($0.023/GB-month), while DynamoDB offers fast queries for real-time dashboards (single-digit millisecond reads). It's the best of both worlds: cheap long-term storage + fast recent data access."

### 3. Explain your error handling strategy
"Three layers of error handling:
1. **Lambda retries**: 3 automatic retries for transient failures
2. **DLQ**: Failed invocations stored for 14 days for debugging/replay
3. **Step Functions catch blocks**: Errors trigger CloudWatch alarms

This ensures no data loss and full visibility into failures."

### 4. Why date partitioning in S3?
"Date partitioning enables efficient Athena queries. When querying `WHERE year=2025 AND month=12`, Athena only scans December 2025 data—faster and cheaper. It's a standard practice for analytics workloads."

### 5. How would you optimize for production?
"For 10x traffic, I'd:
1. Increase Lambda concurrency limits (reserved concurrency)
2. Enable Lambda provisioned concurrency for predictable latency
3. Add S3 batch writes (buffer multiple records, write once)
4. Switch DynamoDB to provisioned capacity with auto-scaling
5. Add CloudWatch alarms for DLQ depth and Lambda errors"

### 6. Explain least-privilege IAM
"The Lambda has scoped permissions:
- Read ONLY from `raw/*` (can't read processed/)
- Write ONLY to `processed/*` (can't write to raw/)
- PutItem ONLY to enriched-data table (no Scan/Query/Delete)

If the Lambda is compromised, damage is limited to its narrow permissions."

### 7. Why TTL in DynamoDB?
"TTL provides automatic data lifecycle management. Recent data stays hot for 30 days (fast queries), then auto-deletes (cost savings). Historical data remains in S3 for analytics. It's the 80/20 rule: 80% of queries target recent data, 20% target historical."

## Common Pitfalls

### ❌ Not Using S3 Read Permissions
**Wrong**: Lambda only has write permissions to S3
```hcl
Action = ["s3:PutObject"]  # ❌ Can't read original data!
```

**Correct**: Lambda needs read from `raw/` AND write to `processed/`
```hcl
# Read raw/
Action = ["s3:GetObject"]
Resource = "${bucket_arn}/raw/*"

# Write processed/
Action = ["s3:PutObject"]
Resource = "${bucket_arn}/processed/*"
```

### ❌ DynamoDB TTL as String
**Wrong**:
```json
{
  "expiresAt": {"S": "2025-12-07T10:30:00Z"}  # ❌ String won't work
}
```

**Correct**:
```json
{
  "expiresAt": {"N": "1733590800"}  # ✅ Unix epoch (seconds)
}
```

### ❌ Forgetting DLQ Permissions
**Wrong**: Lambda has DLQ configured but no SQS SendMessage permission
```hcl
dead_letter_config {
  target_arn = aws_sqs_queue.dlq.arn  # ❌ Lambda can't write to DLQ!
}
```

**Correct**: Add SQS SendMessage permission to Lambda role
```hcl
Action = ["sqs:SendMessage"]
Resource = aws_sqs_queue.dlq.arn
```

## Dependencies

This module requires:
- [`data_lake` module](../data_lake/): S3 bucket for raw/processed data
- [`hot_store` module](../hot_store/): DynamoDB table for enriched data
- [`step_functions` module](../step_functions/): State machine to invoke Lambda

**Wiring Pattern** ([`envs/dev/main.tf`](../../envs/dev/main.tf)):
```hcl
# 1. Create dependencies first
module "data_lake" { ... }
module "hot_store" { ... }

# 2. Create orchestration module
module "orchestration" {
  source = "../../modules/orchestration"

  data_lake_bucket_name = module.data_lake.bucket_name
  data_lake_bucket_arn  = module.data_lake.bucket_arn
  dynamodb_table_name   = module.hot_store.table_name
  dynamodb_table_arn    = module.hot_store.table_arn
}

# 3. Wire orchestration to Step Functions
module "step_functions" {
  source = "../../modules/step_functions"

  merge_lambda_arn = module.orchestration.lambda_function_arn
}
```

## Downstream: Analytics & Query Layer

The enriched data this Lambda writes feeds the analytics layer:
- Glue crawler catalogs the S3 `processed/` data
- Athena workgroup runs SQL queries over it
- A Chart.js dashboard reads DynamoDB (real-time) + curated S3 + Athena (historical)

## References

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Lambda Error Handling](https://docs.aws.amazon.com/lambda/latest/dg/invocation-retries.html)
- [SQS Dead Letter Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [DynamoDB TTL](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)
- [S3 Date Partitioning Best Practices](https://docs.aws.amazon.com/athena/latest/ug/partitions.html)
