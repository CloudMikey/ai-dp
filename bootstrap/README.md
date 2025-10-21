# Bootstrap - Terraform State Bucket Setup

This directory contains the Terraform configuration to create the S3 bucket that will store the remote state for all environments (dev, staging, production).

## Overview

The bootstrap creates:
- **S3 Bucket** for Terraform state storage with:
  - Versioning enabled (protect against accidental deletion/corruption)
  - AES256 encryption at rest
  - Public access blocked
  - SSL/TLS enforced
  - Lifecycle rules for old versions
  - Native S3 locking support (Terraform >= 1.11.0)

## Prerequisites

- Terraform >= 1.11.0 installed
- AWS CLI configured with appropriate credentials
- AWS Account ID ready

## Initial Setup

### Step 1: Create Variable Values File

Create `terraform.tfvars` in this directory:

```hcl
aws_region     = "us-west-1"
aws_account_id = "123456789012"  # Replace with your AWS Account ID
project_name   = "ai-dp"
```

To get your AWS Account ID:
```powershell
aws sts get-caller-identity --query Account --output text
```

### Step 2: Initialize and Apply

```powershell
# Initialize Terraform
terraform -chdir=bootstrap init

# Review the plan
terraform -chdir=bootstrap plan

# Apply the configuration
terraform -chdir=bootstrap apply
```

When prompted, type `yes` to confirm.

### Step 3: Save the Output

After successful apply, Terraform will output the bucket name and backend configuration. **Save this information!**

```powershell
# View outputs again
terraform -chdir=bootstrap output
```

## Configuration Details

### S3 Bucket Naming

The bucket is named: `tf-state-<ACCOUNT_ID>-<REGION>`

Example: `tf-state-123456789012-us-west-1`

This ensures:
- Global uniqueness (required by S3)
- Easy identification
- No conflicts between accounts/regions

### Versioning

Versioning is **enabled by default** to:
- Protect against accidental state file deletion
- Allow recovery from corrupted state
- Maintain history of infrastructure changes

Old versions are automatically deleted after 90 days (configurable via `noncurrent_version_expiration_days`).

### Security Features

1. **Encryption**: All state files encrypted at rest using AES256
2. **Public Access**: All public access blocked
3. **SSL/TLS**: Only secure connections allowed (enforced via bucket policy)
4. **IAM**: Access controlled via AWS IAM policies

### Native S3 Locking

Terraform >= 1.11.0 supports native S3 locking via `.tflock` files:
- No DynamoDB table required
- Simpler architecture
- Lower costs
- Lock files stored alongside state files in S3

## Next Steps

### 1. Configure Backend for Each Environment

For each environment (dev, stg, prod), you have two options:

#### Option A: Direct Backend Configuration

Update `envs/<ENV>/terraform.tf` backend block:

```hcl
terraform {
  backend "s3" {
    bucket       = "tf-state-123456789012-us-west-1"  # From bootstrap output
    key          = "envs/dev/terraform.tfstate"       # Change per environment
    region       = "us-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

#### Option B: Backend Config Files (Recommended)

Create `envs/<ENV>/backend-<ENV>.hcl` files:

**envs/dev/backend-dev.hcl:**
```hcl
bucket       = "tf-state-123456789012-us-west-1"
key          = "envs/dev/terraform.tfstate"
region       = "us-west-1"
encrypt      = true
use_lockfile = true
```

**envs/stg/backend-stg.hcl:**
```hcl
bucket       = "tf-state-123456789012-us-west-1"
key          = "envs/stg/terraform.tfstate"
region       = "us-west-1"
encrypt      = true
use_lockfile = true
```

**envs/prod/backend-prod.hcl:**
```hcl
bucket       = "tf-state-123456789012-us-west-1"
key          = "envs/prod/terraform.tfstate"
region       = "us-west-1"
encrypt      = true
use_lockfile = true
```

Then initialize with:
```powershell
terraform -chdir=envs/dev init "-backend-config=envs/dev/backend-dev.hcl"
```

### 2. Migrate State to Remote Backend

For each environment directory:

```powershell
# Dev environment
cd envs/dev
terraform init -migrate-state
# Type 'yes' when prompted to migrate state

# Staging environment
cd envs/stg
terraform init -migrate-state

# Production environment
cd envs/prod
terraform init -migrate-state
```

### 3. Verify Remote State

Check that state files appear in S3:

```powershell
aws s3 ls s3://tf-state-123456789012-us-west-1/envs/ --recursive
```

Expected output:
```
envs/dev/terraform.tfstate
envs/stg/terraform.tfstate
envs/prod/terraform.tfstate
```

### 4. Test Locking

Run a plan in one terminal:
```powershell
terraform -chdir=envs/dev plan
```

While it's running, try to run another operation in a second terminal:
```powershell
terraform -chdir=envs/dev plan
```

You should see a lock error message. When the first operation completes, check S3:
```powershell
aws s3 ls s3://tf-state-123456789012-us-west-1/envs/dev/ --recursive
```

You should see `.tflock` files being created and deleted.

## Completion Criteria

✅ **Bootstrap is complete when:**

1. S3 bucket exists in AWS
2. Versioning is enabled on the bucket
3. Each environment has backend configuration
4. State has been migrated from local to S3
5. `.tflock` files appear in S3 during `terraform plan`
6. No DynamoDB table is needed
7. Bootstrap state is saved locally (kept separate from env states)

## Managing the Bootstrap State

The bootstrap itself uses a **local backend** (stored in `bootstrap/terraform.tfstate`).

**Important:**
- Keep `bootstrap/terraform.tfstate` in version control (it's safe, contains no secrets)
- Or store it securely (e.g., encrypted backup)
- If lost, you can import the existing S3 bucket:
  ```powershell
  terraform -chdir=bootstrap import aws_s3_bucket.terraform_state tf-state-123456789012-us-west-1
  ```

## Updating the Bootstrap

To make changes to the state bucket:

```powershell
terraform -chdir=bootstrap plan
terraform -chdir=bootstrap apply
```

## Destroying the Bootstrap (⚠️ DANGER)

**Only do this if you're tearing down the entire project!**

1. First, destroy all environments and migrate their state back to local
2. Then destroy the bootstrap:
   ```powershell
   # Remove lifecycle protection
   # Edit main.tf and remove the prevent_destroy block

   terraform -chdir=bootstrap destroy
   ```

## Troubleshooting

### Error: Bucket name already taken

**Cause:** S3 bucket names are globally unique.

**Solution:**
- Verify you're using the correct AWS Account ID
- Check if the bucket already exists: `aws s3 ls s3://tf-state-<ACCOUNT_ID>-<REGION>`
- If it exists and is yours, import it instead of creating

### Error: Access Denied

**Cause:** Insufficient AWS permissions.

**Required IAM permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutLifecycleConfiguration",
        "s3:PutBucketPolicy"
      ],
      "Resource": "arn:aws:s3:::tf-state-*"
    }
  ]
}
```

### State Locking Not Working

**Cause:** Using Terraform < 1.11.0

**Solution:**
- Update Terraform: `choco upgrade terraform`
- Verify version: `terraform version`
- Should show >= 1.11.0

## Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for state bucket | `us-west-1` | No |
| `project_name` | Project name for tagging | `ai-dp` | No |
| `aws_account_id` | AWS Account ID (12 digits) | - | **Yes** |
| `enable_versioning` | Enable S3 versioning | `true` | No |
| `enable_lifecycle_rules` | Enable lifecycle rules | `true` | No |
| `noncurrent_version_expiration_days` | Days to keep old versions | `90` | No |
| `tags` | Additional tags | `{}` | No |

## Security Best Practices

1. **Never commit AWS credentials** to version control
2. **Use IAM roles** instead of access keys when possible
3. **Enable MFA** for production AWS accounts
4. **Regularly rotate** AWS access keys
5. **Use separate AWS accounts** for dev/stg/prod (recommended)
6. **Monitor S3 bucket** with CloudWatch alarms
7. **Enable CloudTrail** to audit access to the state bucket

## Additional Resources

- [Terraform S3 Backend Docs](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [Terraform 1.11 Release Notes](https://github.com/hashicorp/terraform/releases/tag/v1.11.0)
- [AWS S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
