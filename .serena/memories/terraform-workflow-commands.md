# Terraform Workflow Commands

## Terraform Version
- **Required**: >= 1.11.0 | **Pinned**: 1.13.0 (`.terraform-version`)
- Key feature: Native S3 state locking via `use_lockfile = true` (no DynamoDB needed)

## Primary Workflow (PowerShell on Windows)
```powershell
# 1. Format + Validate (always before plan/apply)
terraform -chdir=envs/dev fmt
terraform -chdir=envs/dev validate

# 2. Plan
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev plan -out=tfplan     # Save for review

# 3. Apply
terraform -chdir=envs/dev apply
terraform -chdir=envs/dev apply tfplan          # Apply saved plan

# 4. Init (after clone or backend changes)
terraform -chdir=envs/dev init
terraform -chdir=envs/dev init -migrate-state   # After backend.tf changes
```

## Linting & Security Scanning
```powershell
# TFLint (enforces naming, types, docs, AWS rules)
tflint --chdir=envs/dev

# Tfsec (security scanning)
tfsec envs/dev

# Checkov (via MCP tool or CLI)
checkov -d envs/dev
```

## State Management
```powershell
terraform -chdir=envs/dev state list
terraform -chdir=envs/dev state show <resource>
terraform -chdir=envs/dev state mv <src> <dst>
terraform -chdir=envs/dev state rm <resource>
terraform -chdir=envs/dev output
terraform -chdir=envs/dev output -json
```

## Destroy (DANGEROUS - confirm with user)
```powershell
terraform -chdir=envs/dev destroy
terraform -chdir=envs/dev destroy -target=<resource>
```

## Debug
```powershell
$env:TF_LOG="DEBUG"
$env:TF_LOG_PATH="terraform.log"
terraform -chdir=envs/dev plan
```

## Load Testing
```powershell
python scripts/load_test.py     # Sends 25 events to Kinesis via boto3
```

## API Testing
```bash
# Streaming ingestion
curl -X POST "https://pvqb2gzg7i.execute-api.us-west-2.amazonaws.com/ingest" \
  -H "Content-Type: application/json" -H "X-Partition-Key: test" \
  -d '{"event_type":"test","event_timestamp":"2026-01-25T12:00:00Z"}'

# Batch ingestion
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json
```

## Windows/PowerShell Utilities
```powershell
ls, dir          # List directory
cat, Get-Content # Read file
New-Item         # Create file/directory
Remove-Item      # Delete file/directory
$env:VAR="val"   # Set environment variable
```

## Best Practices
1. Always run `fmt` before committing: `terraform fmt -recursive`
2. Review plans carefully, especially destroy operations
3. Use `-target` sparingly — prefer full plans
4. Never commit `.tfstate` or `.tfvars` with sensitive data
5. Separate environments with separate directories (not workspaces)
