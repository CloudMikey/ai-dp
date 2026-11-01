# Deploying AI-DP

**Prerequisites:** Terraform >= 1.11 (CI uses 1.13.0), AWS CLI with admin-level credentials, Python 3.11, and an AWS account where Comprehend is available in us-west-2.

1. **Create the state bucket** (one time):
   ```bash
   cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars   # set aws_account_id
   terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply
   ```
2. **Point the dev environment at it:**
   ```bash
   cp envs/dev/backend-dev.hcl.example envs/dev/backend-dev.hcl   # set bucket = bootstrap output
   echo 'alarm_email = "you@example.com"' > envs/dev/terraform.tfvars
   ```
3. **CI/CD role (optional):** `envs/dev/cicd.tf` creates the GitHub Actions deploy role and expects a GitHub OIDC provider to already exist in the account. If you don't need CI/CD, add `enable_github_oidc = false` to `terraform.tfvars`.
4. **Deploy:**
   ```bash
   terraform -chdir=envs/dev init -backend-config=backend-dev.hcl
   terraform -chdir=envs/dev apply
   ```
   Then confirm the SNS subscription email so the alarms can reach you.
5. **Try it:**
   ```bash
   curl -X POST "$(terraform -chdir=envs/dev output -raw api_gateway_invoke_url)" \
     -H "Content-Type: application/json" -H "X-Partition-Key: test" \
     -d '{"event_type":"review","event_timestamp":"2026-10-04T12:00:00Z","text":"Fast shipping, great product."}'
   aws s3 cp review.txt s3://$(terraform -chdir=envs/dev output -raw data_lake_bucket_name)/raw/batch/review.txt   # plain text, under 5,000 bytes
   ```

## Teardown

Both the data lake and the Athena results bucket have versioning on and no `force_destroy`, so `terraform destroy` fails until they're empty. Empty them first, including old versions (the S3 console's **Empty** button does this), then run `terraform -chdir=envs/dev destroy`, and destroy `bootstrap/` last.
