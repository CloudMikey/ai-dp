# Analytics Module

This module provides AWS Glue Data Catalog and Amazon Athena infrastructure for querying enriched data stored in S3.

## Overview

The analytics module enables SQL-based queries on the AI-enriched data pipeline using:
- **AWS Glue Crawler**: Automatically discovers schema and partitions from S3 JSON files
- **AWS Glue Data Catalog**: Stores table metadata (acts as a Hive metastore)
- **Amazon Athena**: Serverless SQL query engine
- **S3 Results Bucket**: Stores Athena query outputs (auto-deleted after 7 days)

## Architecture

```
S3 processed/ (JSON files)
    ↓
Glue Crawler (on-demand)
    ↓
Glue Data Catalog (table metadata)
    ↓
Athena Workgroup (SQL queries)
    ↓
S3 Results Bucket (query outputs)
```

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| Glue Database | `ai-dp-dev-analytics` | Logical grouping for tables |
| Glue Crawler | `ai-dp-dev-crawler` | Schema discovery and partition detection |
| Athena Workgroup | `ai-dp-dev-workgroup` | Query execution environment |
| S3 Bucket | `ai-dp-athena-results-dev-us-west-2` | Temporary query results storage |
| IAM Role | `ai-dp-dev-glue-crawler-role` | Crawler execution permissions |

## Features

### Automatic Schema Discovery
The Glue Crawler:
- Infers schema from JSON files (no manual DDL required)
- Detects partitions automatically (`year=*/month=*/day=*`)
- Updates schema when new fields appear (e.g., additional Comprehend features)

### Partition Pruning
Athena queries can filter by date partitions to reduce data scanned:
```sql
SELECT * FROM processed
WHERE year='2025' AND month='12' AND day='16'
```

### Cost Optimization
- **On-demand crawler**: Only runs when triggered (no scheduled costs)
- **7-day query results expiration**: Automatic cleanup prevents storage bloat
- **Partition detection**: Enables efficient query filtering

## Usage

### Running the Crawler

```bash
# Start crawler manually
aws glue start-crawler --name ai-dp-dev-crawler --region us-west-2

# Check crawler status
aws glue get-crawler --name ai-dp-dev-crawler --region us-west-2

# Wait until state = "READY" (usually 1-2 minutes)
```

### Querying with Athena

```sql
-- View all data (limited)
SELECT * FROM ai_dp_dev_analytics.processed LIMIT 10;

-- Sentiment distribution
SELECT sentiment, COUNT(*) as count
FROM ai_dp_dev_analytics.processed
GROUP BY sentiment;

-- Events by date
SELECT year, month, day, COUNT(*) as event_count
FROM ai_dp_dev_analytics.processed
GROUP BY year, month, day
ORDER BY year DESC, month DESC, day DESC;

-- Filter by partition (cost-efficient)
SELECT *
FROM ai_dp_dev_analytics.processed
WHERE year='2025' AND month='12'
LIMIT 100;
```

## Inputs

| Variable | Type | Description | Required |
|----------|------|-------------|----------|
| `project_name` | string | Project name for resource naming | Yes |
| `environment` | string | Environment (dev/stg/prod) | Yes |
| `aws_region` | string | AWS region | Yes |
| `data_lake_bucket_name` | string | S3 data lake bucket name | Yes |
| `data_lake_bucket_arn` | string | S3 data lake bucket ARN | Yes |
| `tags` | map(string) | Additional tags | No |

## Outputs

| Output | Description |
|--------|-------------|
| `database_name` | Glue Data Catalog database name |
| `crawler_name` | Glue Crawler name |
| `workgroup_name` | Athena workgroup name |
| `athena_results_bucket` | S3 bucket for query results |
| `table_name` | Expected table name (after crawler runs) |

## Schema Evolution

The crawler uses `UPDATE_IN_DATABASE` schema change policy:
- **New fields added**: Table schema automatically updated on next crawl
- **Fields removed**: Schema updated (existing queries may fail)
- **Field type changed**: Crawler creates a new table version

## Best Practices

### When to Run the Crawler

1. **After initial deployment** - Populate the initial schema
2. **After schema changes** - When adding new AI enrichment services
3. **After adding new partitions** - If partition detection fails (rare)
4. **Weekly/Monthly** - For large datasets with infrequent changes

### Query Optimization

```sql
-- ✅ GOOD: Uses partition pruning
SELECT * FROM processed
WHERE year='2025' AND month='12'
LIMIT 100;

-- ❌ BAD: Scans all data
SELECT * FROM processed
WHERE timestamp > 1234567890
LIMIT 100;
```

### Monitoring

- **CloudWatch Metrics**: Athena workgroup publishes query metrics
- **Glue Crawler Logs**: Check `/aws-glue/crawlers` log group
- **Athena Query History**: View in Athena console

## Cost Considerations

| Service | Pricing | Dev Environment Cost (Estimate) |
|---------|---------|--------------------------------|
| Glue Crawler | $0.44/DPU-hour | ~$0.10 per run (5 min @ 2 DPUs) |
| Athena Queries | $5 per TB scanned | ~$0.01 per query (with partitions) |
| S3 Storage (results) | $0.023/GB-month | ~$0.10/month (auto-deleted) |
| Data Catalog | First 1M objects free | $0 (portfolio use) |

**Total estimated cost for dev:** < $5/month with moderate usage

## Troubleshooting

### Crawler Fails to Detect Partitions

**Symptom**: Table created but no partitions visible

**Solution**:
```sql
-- Manually add partitions if auto-detection fails
MSCK REPAIR TABLE ai_dp_dev_analytics.processed;
```

### Athena Query Returns No Results

**Symptom**: Query runs but returns 0 rows

**Checklist**:
1. Has the crawler run successfully? Check Glue console
2. Are there files in S3 `processed/`? Verify via S3 console
3. Is the table schema correct? Run `DESCRIBE processed;`
4. Are partitions registered? Run `SHOW PARTITIONS processed;`

### Schema Mismatch Errors

**Symptom**: `HIVE_PARTITION_SCHEMA_MISMATCH` error

**Cause**: Partition schema differs from table schema (common with evolving data)

**Solution**: Re-run crawler to update schema, or drop and recreate table

## Example: Full Workflow

```bash
# 1. Deploy module
terraform -chdir=envs/dev apply

# 2. Run crawler (wait ~2 minutes)
aws glue start-crawler --name ai-dp-dev-crawler --region us-west-2

# 3. Check status
aws glue get-crawler --name ai-dp-dev-crawler --region us-west-2

# 4. Query with Athena (AWS Console or CLI)
aws athena start-query-execution \
  --query-string "SELECT * FROM ai_dp_dev_analytics.processed LIMIT 10" \
  --work-group ai-dp-dev-workgroup \
  --region us-west-2
```
