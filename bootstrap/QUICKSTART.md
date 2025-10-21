# Bootstrap Quick Start Guide

This is a quick reference for setting up the Terraform S3 backend. For detailed information, see [README.md](README.md).

## 🚀 Quick Setup (5 minutes)

### Step 1: Get Your AWS Account ID

```powershell
aws sts get-caller-identity --query Account --output text
```

### Step 2: Create Configuration File

Copy the example file:
```powershell
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
```

Edit `bootstrap/terraform.tfvars`:
```hcl
aws_region     = "us-west-1"
aws_account_id = "YOUR_ACCOUNT_ID_HERE"  # From Step 1
project_name   = "ai-dp"
```

### Step 3: Deploy the S3 Bucket

```powershell
# Initialize
terraform -chdir=bootstrap init

# Plan (review what will be created)
terraform -chdir=bootstrap plan

# Apply (create the bucket)
terraform -chdir=bootstrap apply
```

Type `yes` when prompted.

### Step 4: Save the Bucket Name

After successful apply, note the bucket name from the output:
```
s3_bucket_name = "tf-state-123456789012-us-west-1"
```

### Step 5: Configure Backend for Each Environment

For each environment (dev, stg, prod):

1. Copy the example backend config:
   ```powershell
   # Dev
   cp envs/dev/backend-dev.hcl.example envs/dev/backend-dev.hcl

   # Staging
   cp envs/stg/backend-stg.hcl.example envs/stg/backend-stg.hcl

   # Production
   cp envs/prod/backend-prod.hcl.example envs/prod/backend-prod.hcl
   ```

2. Edit each file and replace `ACCOUNT_ID` and `REGION` with your values:
   ```hcl
   bucket       = "tf-state-123456789012-us-west-1"  # Use actual bucket name
   key          = "envs/dev/terraform.tfstate"       # Leave as-is (changes per env)
   region       = "us-west-1"                         # Your region
   encrypt      = true
   use_lockfile = true
   ```

### Step 6: Initialize Each Environment

```powershell
# Dev environment
terraform -chdir=envs/dev init "-backend-config=envs/dev/backend-dev.hcl"

# Staging environment
terraform -chdir=envs/stg init "-backend-config=envs/stg/backend-stg.hcl"

# Production environment
terraform -chdir=envs/prod init "-backend-config=envs/prod/backend-prod.hcl"
```

If you have existing state, type `yes` when prompted to migrate.

## ✅ Verify Setup

Check that state files are in S3:
```powershell
aws s3 ls s3://tf-state-123456789012-us-west-1/envs/ --recursive
```

Expected output:
```
envs/dev/terraform.tfstate
envs/stg/terraform.tfstate
envs/prod/terraform.tfstate
```

## 🧪 Test Locking

In one terminal:
```powershell
terraform -chdir=envs/dev plan
```

In another terminal (while first is running):
```powershell
terraform -chdir=envs/dev plan
```

You should see a lock error! ✅ This means locking is working.

Check for lock files in S3:
```powershell
aws s3 ls s3://tf-state-123456789012-us-west-1/envs/dev/ --recursive
```

You should see `.tflock` files being created/deleted.

## 📋 Common Commands Reference

```powershell
# View bootstrap outputs
terraform -chdir=bootstrap output

# Check Terraform version (must be >= 1.11.0)
terraform version

# Verify AWS credentials
aws sts get-caller-identity

# List contents of state bucket
aws s3 ls s3://tf-state-ACCOUNT_ID-REGION/ --recursive

# Force unlock (if needed - use carefully!)
terraform -chdir=envs/dev force-unlock LOCK_ID
```

## 🎯 Completion Criteria

Your bootstrap is complete when:

- [x] S3 bucket exists in AWS
- [x] Versioning is enabled on the bucket
- [x] Each environment has `backend-<env>.hcl` file configured
- [x] State has been migrated from local to S3
- [x] `.tflock` files appear in S3 during `terraform plan`
- [x] No DynamoDB table is needed or created
- [x] Bootstrap state is saved locally in `bootstrap/terraform.tfstate`

## ⚠️ Troubleshooting

**"Bucket already exists"**
- Check if you already created it: `aws s3 ls | grep tf-state`
- Use `terraform import` if the bucket is yours

**"Access Denied"**
- Verify AWS credentials: `aws sts get-caller-identity`
- Ensure you have S3 permissions (CreateBucket, PutBucketVersioning, etc.)

**"Module not initialized"**
- Run `terraform init` in the appropriate directory

**"Backend initialization required"**
- Run `terraform init -backend-config=backend-<env>.hcl`

## 📚 Next Steps

After bootstrap is complete:

1. Read the [main README](../README.md) for project overview
2. Review [CLAUDE.md](../CLAUDE.md) for development guidelines
3. Start implementing Terraform modules in `modules/`
4. Run linters before committing: `tflint --recursive && tfsec .`

## 🔗 Related Documentation

- [Bootstrap README](README.md) - Detailed documentation
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [Terraform 1.11 Native Locking](https://github.com/hashicorp/terraform/releases/tag/v1.11.0)
