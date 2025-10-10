# Terraform Workflow Commands

## Project Terraform Version
- **Required**: >= 1.11.0 (specified in `.terraform-version` file: 1.13.0)
- **Key Feature**: Native S3 state locking via `use_lockfile = true` (no DynamoDB table needed)

## Environment-Specific Commands

All Terraform commands use the `-chdir` flag to target specific environments:

### Initialize Environment
```powershell
terraform -chdir=envs/dev init
terraform -chdir=envs/stg init
terraform -chdir=envs/prod init
```

Initializes backend, downloads providers, and modules. Run after:
- Initial clone of repository
- Backend configuration changes
- Provider version updates

### Format and Validate
```powershell
# Format Terraform files (auto-fix)
terraform -chdir=envs/dev fmt

# Validate configuration syntax
terraform -chdir=envs/dev validate
```

### Plan Changes
```powershell
# Preview changes without applying
terraform -chdir=envs/dev plan

# Save plan to file for review
terraform -chdir=envs/dev plan -out=tfplan

# Plan with specific var file
terraform -chdir=envs/dev plan -var-file=terraform.tfvars
```

### Apply Changes
```powershell
# Apply with interactive approval
terraform -chdir=envs/dev apply

# Apply saved plan file (no approval needed)
terraform -chdir=envs/dev apply tfplan

# Auto-approve (use in CI/CD only)
terraform -chdir=envs/dev apply -auto-approve
```

### Destroy Resources
```powershell
# Destroy all resources (DANGEROUS)
terraform -chdir=envs/dev destroy

# Destroy specific resource
terraform -chdir=envs/dev destroy -target=module.data_lake.aws_s3_bucket.raw
```

### State Management
```powershell
# List resources in state
terraform -chdir=envs/dev state list

# Show specific resource details
terraform -chdir=envs/dev state show module.data_lake.aws_s3_bucket.raw

# Move resource in state (refactoring)
terraform -chdir=envs/dev state mv <source> <destination>

# Remove resource from state (doesn't destroy)
terraform -chdir=envs/dev state rm <resource>

# Pull remote state to local file
terraform -chdir=envs/dev state pull > terraform.tfstate.backup
```

### Output Values
```powershell
# Show all outputs
terraform -chdir=envs/dev output

# Show specific output
terraform -chdir=envs/dev output raw_bucket_name

# Output as JSON
terraform -chdir=envs/dev output -json > outputs.json
```

### Workspace Commands
(Not currently used in this project - using separate directories instead)
```powershell
terraform workspace list
terraform workspace select dev
terraform workspace new staging
```

## CI/CD Workflow (Planned)

### Pull Request Workflow
```yaml
# On every PR
terraform -chdir=envs/dev fmt -check     # Fail if not formatted
terraform -chdir=envs/dev validate       # Validate syntax
terraform -chdir=envs/dev plan           # Show changes
# Additional: tflint, tfsec security scanning
```

### Deployment Workflow
```yaml
# On merge to main
1. Assume AWS role via OIDC (no long-term credentials)
2. terraform -chdir=envs/dev init
3. terraform -chdir=envs/dev apply -auto-approve
4. Manual approval gate
5. terraform -chdir=envs/stg apply -auto-approve
6. Manual approval gate
7. terraform -chdir=envs/prod apply -auto-approve
```

## Backend Migration Commands

### Migrate from Local to S3 Backend
```powershell
# After adding backend.tf configuration
terraform -chdir=envs/dev init -migrate-state
```

### Reconfigure Backend
```powershell
# Force backend reconfiguration
terraform -chdir=envs/dev init -reconfigure

# Update backend without copying state
terraform -chdir=envs/dev init -backend=false
```

## Troubleshooting Commands

### Lock Issues
```powershell
# Force unlock (use with extreme caution)
terraform -chdir=envs/dev force-unlock <LOCK_ID>
```

### Refresh State
```powershell
# Update state with real infrastructure (deprecated in newer versions)
terraform -chdir=envs/dev refresh

# Modern approach: use -refresh-only flag
terraform -chdir=envs/dev apply -refresh-only
```

### Debug Output
```powershell
# Enable debug logging
$env:TF_LOG="DEBUG"
terraform -chdir=envs/dev plan

# Log to file
$env:TF_LOG="DEBUG"
$env:TF_LOG_PATH="terraform.log"
terraform -chdir=envs/dev apply
```

## Module Development Commands

### Testing Module Locally
```powershell
# Navigate to module directory
cd modules/data_lake

# Format
terraform fmt

# Validate (requires example/test configuration)
terraform validate

# Return to root
cd ../..
```

## Best Practices

1. **Always run `fmt` before committing**: `terraform fmt -recursive`
2. **Review plans carefully**: Especially for destroy operations
3. **Use `-target` sparingly**: Prefer full plans for safety
4. **Keep state in sync**: Never manually edit state files
5. **Lock state during operations**: Native locking via `use_lockfile = true` handles this automatically
6. **Separate environments**: Use different directories (envs/dev, envs/stg, envs/prod), not workspaces
7. **Version control**: Never commit `.tfstate` files or `.tfvars` with sensitive data