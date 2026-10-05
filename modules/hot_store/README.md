# DynamoDB Hot Store Module

Creates a DynamoDB table for storing AI-enriched data with fast query capabilities.

## Purpose

The hot store maintains recent enriched data (last 30 days by default) for:
- **Real-time dashboards**: Recent events visible within seconds
- **Time-based analytics**: Query by date range using GSI
- **Data retention**: TTL auto-deletes old records (archives remain in S3)

## Architecture

**Primary Key**:
- Partition Key: `recordId` (String) - Unique record identifier
- Sort Key: `timestamp` (Number) - Unix epoch milliseconds

**Global Secondary Index** (`timestamp-index`):
- Partition Key: `recordType` (String) - Data type filter
- Sort Key: `timestamp` (Number) - Time-based range queries
- Projection: ALL attributes

**Example Query Pattern**:
```
"Get all text records from the last 7 days"
→ Query GSI: recordType = 'text' AND timestamp BETWEEN (now-7d) AND now
```

## Table Schema Example

```json
{
  "recordId": "2025-01-24T10:30:00Z-abc123",
  "timestamp": 1737715800000,
  "recordType": "text",
  "sentiment": "POSITIVE",
  "sentimentScore": 0.95,
  "entities": ["AWS", "Terraform", "DynamoDB"],
  "rawDataLocation": "s3://bucket/raw/year=2025/month=01/day=24/data.json",
  "processedDataLocation": "s3://bucket/processed/year=2025/month=01/day=24/enriched.json",
  "expiresAt": 1740393600
}
```

## Features

- **On-demand billing**: No capacity planning, scales automatically
- **Point-in-time recovery**: 35-day backup retention for disaster recovery
- **TTL**: Auto-deletes records after 30 days (configurable)
- **GSI**: Efficient time-based queries without full table scan
- **Encryption**: Default encryption at rest (AWS-managed keys)

## Usage

```hcl
module "hot_store" {
  source = "../../modules/hot_store"

  environment  = "dev"
  project_name = "ai-dp"
  aws_region   = "us-west-2"

  enable_point_in_time_recovery = true
  enable_ttl                     = true
  ttl_days                       = 30

  tags = {
    Component = "Storage"
  }
}
```

## Outputs

- `table_name`: DynamoDB table name
- `table_arn`: Table ARN (for IAM policies)
- `gsi_name`: GSI name for time-based queries
- `ttl_attribute_name`: TTL attribute name (`expiresAt`)
- `ttl_days`: TTL expiration period

## Cost Optimization

**On-demand billing** charges:
- $0.25 per million write requests
- $0.25 per million read requests
- $0.25 per GB-month storage

**Dev environment estimate** (1000 records/day, 30 days retention):
- Storage: 30,000 records × 2 KB = ~60 MB = **$0.015/month**
- Writes: 30,000/month = **$0.0075/month**
- Reads: 10,000/month = **$0.0025/month**
- **Total: ~$0.03/month** (negligible for portfolio project)

## Security Considerations

**IAM Policy** (used by the Merge Lambda):
```hcl
# Least-privilege policy (scoped to specific table)
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem"
      ]
      Resource = module.hot_store.table_arn
    }
  ]
})
```

**Why Least-Privilege**:
- Only PutItem (write), GetItem (read), UpdateItem (modify)
- NO DeleteItem (prevent accidental deletion)
- NO Scan/Query (Merge Lambda doesn't need full table access)
- Scoped to specific table ARN (can't access other DynamoDB tables)

## Testing

### Test 1: CRUD Operations
```powershell
# Write record
aws dynamodb put-item `
  --table-name ai-dp-dev-enriched-data `
  --item '{\"recordId\": {\"S\": \"test-001\"}, \"timestamp\": {\"N\": \"1737715800000\"}, \"recordType\": {\"S\": \"text\"}}' `
  --region us-west-2

# Read record
aws dynamodb get-item `
  --table-name ai-dp-dev-enriched-data `
  --key '{\"recordId\": {\"S\": \"test-001\"}, \"timestamp\": {\"N\": \"1737715800000\"}}' `
  --region us-west-2
```

### Test 2: GSI Query
```powershell
# Query all text records
aws dynamodb query `
  --table-name ai-dp-dev-enriched-data `
  --index-name timestamp-index `
  --key-condition-expression \"recordType = :type\" `
  --expression-attribute-values '{\":type\": {\"S\": \"text\"}}' `
  --region us-west-2
```

### Test 3: Verify TTL
```powershell
aws dynamodb describe-time-to-live `
  --table-name ai-dp-dev-enriched-data `
  --region us-west-2
```

### Test 4: Verify PITR
```powershell
aws dynamodb describe-continuous-backups `
  --table-name ai-dp-dev-enriched-data `
  --region us-west-2
```

## Common Pitfalls

### ❌ Defining Non-Key Attributes
**Wrong**:
```hcl
attribute {
  name = "sentiment"  # ❌ Not a key, don't define
  type = "S"
}
```

**Correct**: Only define attributes used in partition key, sort key, or GSI keys

### ❌ TTL Attribute Wrong Type
**Wrong**:
```json
{
  "expiresAt": {"S": "2025-02-23"}  # ❌ String, won't work
}
```

**Correct**:
```json
{
  "expiresAt": {"N": "1740393600"}  # ✅ Number (Unix epoch seconds)
}
```

## Pipeline Integration

- **AI Enrichment** — Step Functions calls Amazon Comprehend for sentiment + entity detection.
- **Merge Lambda** — writes the enriched records to both S3 `processed/` and this DynamoDB table (real-time hot store).
