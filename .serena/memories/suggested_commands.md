# Suggested Commands for Development

## Terraform (Primary Workflow)
```powershell
# Format + Validate (always first)
terraform -chdir=envs/dev fmt && terraform -chdir=envs/dev validate

# Plan & Apply
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev apply

# Init (after clone or backend/provider changes)
terraform -chdir=envs/dev init
```

## Linting & Security
```powershell
tflint --chdir=envs/dev          # Terraform linting
tfsec envs/dev                   # Security scanning
checkov -d envs/dev              # Compliance scanning (or via MCP tool)
```

## Testing
```powershell
# Lambda unit tests (from lambdas/ directory)
python -m pytest lambdas/ -v

# Load test (25 events to Kinesis)
python scripts/load_test.py
```

## AWS CLI (Bash syntax)
```bash
# Check deployed resources
aws kinesis describe-stream-summary --stream-name ai-dp-dev-ingestion-stream --region us-west-2
aws dynamodb describe-table --table-name ai-dp-dev-enriched-data --region us-west-2
aws s3 ls s3://ai-dp-data-lake-dev-us-west-2/

# Test API endpoint
curl -X POST "https://pvqb2gzg7i.execute-api.us-west-2.amazonaws.com/ingest" \
  -H "Content-Type: application/json" -H "X-Partition-Key: test" \
  -d '{"event_type":"test","event_timestamp":"2026-01-25T12:00:00Z"}'

# Batch ingestion test
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json
```

## Git (Windows PowerShell)
```powershell
git status
git add <files>
git commit -m "message"
git push origin main
git log --oneline -10
```

## Task Completion Checklist
1. `terraform -chdir=envs/dev fmt` — format code
2. `terraform -chdir=envs/dev validate` — validate syntax
3. `tflint --chdir=envs/dev` — lint check
4. `terraform -chdir=envs/dev plan` — review changes
5. Update `docs/status.md` and `docs/roadmap.md` if phase completed
6. Update `docs/errorlog.md` if any errors encountered
