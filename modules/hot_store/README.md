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
  aws_region   = "us-west-1"

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

## Interview Talking Points

### 1. Why DynamoDB over RDS?
"DynamoDB scales horizontally for high-throughput workloads. For enriched event data, we need fast writes and time-based queries, which DynamoDB handles better than relational databases."

### 2. Why on-demand billing?
"For a portfolio project with unpredictable traffic, on-demand eliminates capacity planning overhead. In production, I'd analyze traffic patterns and consider provisioned capacity with auto-scaling for cost optimization."

### 3. Why TTL?
"TTL provides automatic data lifecycle management. Recent data stays in DynamoDB for fast queries, but we don't pay to store old data indefinitely since it's already archived in S3."

### 4. Why GSI on recordType + timestamp?
"The GSI supports common analytics queries like 'show all text records from last week' without scanning the entire table. It's optimized for time-based filtering, which is our primary query pattern."

### 5. Point-in-time recovery worth the cost?
"For $0.20/GB-month, PITR provides 35 days of backup. If the table gets corrupted or accidentally deleted, we can restore to any point in time. It's cheap insurance for data integrity."

### 6. Explain your partition key choice
"I chose `recordId` as the partition key to ensure even distribution across partitions—no hot keys. Each record has a unique ID, so read/write traffic spreads evenly. The sort key `timestamp` allows querying multiple versions of a record if needed."

### 7. How would you scale this for production?
"For 10x traffic, I'd:
1. Monitor read/write patterns, consider provisioned capacity
2. Enable DynamoDB auto-scaling
3. Add partition key sharding for GSI if seeing hot partitions
4. Enable DAX (caching) if read-heavy
5. Archive older data more aggressively (14-day TTL vs 30)"

## Security Considerations

**IAM Policy** (Phase 7 - Merge Lambda):
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
  --region us-west-1

# Read record
aws dynamodb get-item `
  --table-name ai-dp-dev-enriched-data `
  --key '{\"recordId\": {\"S\": \"test-001\"}, \"timestamp\": {\"N\": \"1737715800000\"}}' `
  --region us-west-1
```

### Test 2: GSI Query
```powershell
# Query all text records
aws dynamodb query `
  --table-name ai-dp-dev-enriched-data `
  --index-name timestamp-index `
  --key-condition-expression \"recordType = :type\" `
  --expression-attribute-values '{\":type\": {\"S\": \"text\"}}' `
  --region us-west-1
```

### Test 3: Verify TTL
```powershell
aws dynamodb describe-time-to-live `
  --table-name ai-dp-dev-enriched-data `
  --region us-west-1
```

### Test 4: Verify PITR
```powershell
aws dynamodb describe-continuous-backups `
  --table-name ai-dp-dev-enriched-data `
  --region us-west-1
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

## Next Phase

**Phase 6: AI Enrichment** - Step Functions calls Amazon Comprehend for sentiment analysis

**Phase 7: Merge Lambda** - Writes enriched data to both S3 `processed/` AND this DynamoDB table
