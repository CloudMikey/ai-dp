# Orchestration Module

Creates the Merge Lambda function that combines AI enrichment results and implements the **dual storage strategy** (S3 processed layer + DynamoDB hot store).

## Purpose

The orchestration module completes the data pipeline by:
- **Merging AI outputs**: Combines sentiment analysis and entity extraction results from Amazon Comprehend
- **Dual-write pattern**: Writes enriched data to both S3 `processed/` (historical analytics) and DynamoDB (real-time queries)
- **Error handling**: failures surface to Step Functions, which retries transient Lambda errors and routes the rest to `MergeFailed`
- **Metadata enrichment**: Adds processing timestamps, Lambda version info, and record versioning

## Architecture

### Data Flow

```
Step Functions (InvokeMergeLambda)
  ↓
Merge Lambda receives:
  - source_object: bucket + key of the raw/ file
  - ai_enrichment: raw DetectSentiment + DetectEntities responses
  - processing_metadata: execution timestamp + state machine name
  ↓
Reads the raw/ file only to build a 500-char text preview
  ↓
Builds one enriched record (recordId, sentiment, scores, entities)
  ↓
Writes, in order:
  1. S3 processed/year=/month=/day=/ (full record, for Athena)
  2. DynamoDB (dashboard fields, 30-day TTL)
  3. S3 curated/latest_summary.json (running totals; non-fatal, conditional write)
```

### Merge Lambda Responsibilities

1. **Text preview**: Reads the raw file and keeps the `text` field (JSON events) or the whole body (plain text)
2. **Combine outputs**: Builds one record from the sentiment and entity responses, keeping only meaningful entity types (person, place, organization, ...) in `entities`
3. **Add metadata**: `recordId`, `mergedAt`, `lambdaVersion`, `lambdaName`
4. **Date partition**: Writes to S3 `processed/year=YYYY/month=MM/day=DD/`
5. **Set TTL**: Calculates `expiresAt` for DynamoDB auto-deletion (30 days default)
6. **Error handling**: Raises on failure so Step Functions can retry or catch it

## Features

- **Dual Storage Strategy**: S3 for cost-effective historical queries, DynamoDB for fast real-time access
- **Retries**: Step Functions retries `Lambda.ServiceException` / `Lambda.TooManyRequestsException` 3 times with backoff
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

Step Functions invokes this Lambda **synchronously**, so a Lambda dead-letter queue would never receive anything (`dead_letter_config` only applies to asynchronous invocations). Failures are handled by the state machine:

1. **Retry**: `Lambda.ServiceException` and `Lambda.TooManyRequestsException` are retried 3 times (2s, then backoff 2.0).
2. **Catch**: anything else, or retries exhausted, routes the execution to the `MergeFailed` state.
3. **Alert**: failed executions trigger the `step-functions-failures` alarm. See `docs/runbooks.md` (3d and 5) to inspect and replay them.

The curated-summary update is the one non-fatal step: if it fails, the record is still in S3 and DynamoDB, and `scripts/rebuild_summary.py` can recompute the summary.

### Monitoring Failed Invocations

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
