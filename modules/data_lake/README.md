# Data Lake Module

## Overview

This Terraform module creates an S3-based data lake with three logical layers using prefix-based organization:

- **raw/**: Ingested data from Kinesis streams or batch uploads
- **processed/**: AI-enriched data ready for analytics
- **curated/**: Aggregated, business-ready datasets

## Features

- Single S3 bucket with prefix-based layer separation
- Server-side encryption (SSE-S3 or KMS)
- Versioning enabled by default
- Public access blocking (all 4 settings enabled)
- TLS-only access enforcement via bucket policy
- Lifecycle policies for cost optimization:
  - **Raw layer**: Transitions to IA after 30 days, Glacier after 90 days, expires after 365 days
  - **Processed layer**: Transitions to IA after 60 days, Glacier after 180 days, expires after 730 days
  - **Curated layer**: No transitions by default (frequently accessed)

## Usage

### Basic Example

```hcl
module "data_lake" {
  source = "../../modules/data_lake"

  environment  = "dev"
  project_name = "aidp"
  aws_region   = "us-west-2"

  tags = {
    Owner = "DataTeam"
    CostCenter = "Engineering"
  }
}
```

### With KMS Encryption

```hcl
module "data_lake" {
  source = "../../modules/data_lake"

  environment  = "prod"
  project_name = "aidp"
  aws_region   = "us-west-2"
  kms_key_arn  = aws_kms_key.data_lake.arn

  tags = {
    Owner = "DataTeam"
    CostCenter = "Engineering"
  }
}
```

### Custom Lifecycle Policies

```hcl
module "data_lake" {
  source = "../../modules/data_lake"

  environment  = "dev"
  project_name = "aidp"
  aws_region   = "us-west-2"

  raw_layer_lifecycle = {
    transition_to_ia_days      = 15
    transition_to_glacier_days = 45
    expiration_days            = 180
  }

  processed_layer_lifecycle = {
    transition_to_ia_days      = 30
    transition_to_glacier_days = 90
    expiration_days            = 365
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name (dev, stg, prod) | `string` | n/a | yes |
| project_name | Project name used in resource naming | `string` | `"aidp"` | no |
| aws_region | AWS region for the data lake | `string` | n/a | yes |
| kms_key_arn | Optional KMS key ARN for bucket encryption | `string` | `null` | no |
| enable_versioning | Enable S3 bucket versioning | `bool` | `true` | no |
| raw_layer_lifecycle | Lifecycle configuration for raw data layer | `object` | See variables.tf | no |
| processed_layer_lifecycle | Lifecycle configuration for processed data layer | `object` | See variables.tf | no |
| curated_layer_lifecycle | Lifecycle configuration for curated data layer | `object` | See variables.tf | no |
| tags | Additional tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Name of the data lake S3 bucket |
| bucket_arn | ARN of the data lake S3 bucket |
| bucket_id | ID of the data lake S3 bucket |
| bucket_domain_name | Domain name of the data lake S3 bucket |
| bucket_regional_domain_name | Regional domain name of the data lake S3 bucket |
| raw_prefix | S3 prefix for raw data layer |
| processed_prefix | S3 prefix for processed data layer |
| curated_prefix | S3 prefix for curated data layer |
| raw_bucket_path | Full S3 path to raw data layer |
| processed_bucket_path | Full S3 path to processed data layer |
| curated_bucket_path | Full S3 path to curated data layer |
| versioning_enabled | Whether bucket versioning is enabled |
| encryption_type | Type of encryption used (AES256 or KMS) |

## Bucket Naming Convention

Buckets are named using the pattern: `{project_name}-data-lake-{environment}-{region}`

Example: `aidp-data-lake-dev-us-west-2`

## Security Features

1. **Encryption at Rest**: All data encrypted using SSE-S3 (or KMS if specified)
2. **Encryption in Transit**: Bucket policy enforces TLS-only access
3. **Public Access**: All public access blocked (4/4 settings enabled)
4. **Versioning**: Protects against accidental deletions and overwrites
5. **Lifecycle Policies**: Applies to both current and noncurrent versions

## Cost Optimization

Lifecycle policies automatically transition data to cheaper storage classes:

- **STANDARD** → **STANDARD_IA** (Infrequent Access) → **GLACIER** → **EXPIRATION**
- Noncurrent versions also follow lifecycle rules to prevent cost accumulation

Adjust transition days via lifecycle variables to balance cost vs. access requirements.

## Integration with Other Modules

This module outputs bucket information that can be consumed by:

- **ingestion_stream**: ETL Lambda writes to `raw/`
- **step_functions**: Orchestration reads from `raw/`, AI services write to `processed/`
- **analytics**: Glue crawler catalogs `processed/` and `curated/`
- **hot_store**: Merge Lambda reads from `processed/`

## Testing

After applying this module:

1. Verify bucket exists: `aws s3 ls | grep data-lake`
2. Check encryption: `aws s3api get-bucket-encryption --bucket <bucket-name>`
3. Check versioning: `aws s3api get-bucket-versioning --bucket <bucket-name>`
4. Upload test file: `echo "test" | aws s3 cp - s3://<bucket-name>/raw/test.txt`
5. Verify lifecycle rules: `aws s3api get-bucket-lifecycle-configuration --bucket <bucket-name>`
6. Verify public access block: `aws s3api get-public-access-block --bucket <bucket-name>`

## Viewing Bucket Contents

Use these AWS CLI commands to inspect data in your data lake:

### See Everything Recursively

```bash
aws s3 ls s3://bucket/ --recursive
```

Lists all objects in the bucket with their last modified date and size.

### Add File Sizes & Summary

```bash
aws s3 ls s3://bucket/ --recursive --human-readable --summarize
```

Displays file sizes in human-readable format (KB, MB, GB) and provides a summary with total object count and size.

### Only Show File Paths

```bash
aws s3api list-objects --bucket bucket-name --query "Contents[].Key" --output text
```

Returns just the object keys (file paths) without metadata - useful for scripting or piping to other commands.

### Examples with Data Lake Layers

```bash
# View all raw data
aws s3 ls s3://aidp-data-lake-dev-us-west-2/raw/ --recursive --human-readable

# Check processed data with summary
aws s3 ls s3://aidp-data-lake-dev-us-west-2/processed/ --recursive --summarize

# List only curated file paths
aws s3api list-objects --bucket aidp-data-lake-dev-us-west-2 --query "Contents[].Key" --output text --prefix curated/
```

## Maintenance

- Review lifecycle policies quarterly to optimize costs
- Monitor versioning storage costs (noncurrent versions count towards storage)
- Consider enabling S3 Intelligent-Tiering for unpredictable access patterns

## References

- [S3 Lifecycle Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html)
- [S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
