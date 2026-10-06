# CI/CD Pipeline Documentation

**Last Updated:** 2026-04-05

---

## Overview

This project uses GitHub Actions for automated Terraform validation and deployment. Two workflows cover the full CI/CD lifecycle:

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| CI | `.github/workflows/ci.yml` | PR opened/updated targeting `main` | Validate + plan (no apply) |
| Deploy | `.github/workflows/deploy.yml` | Push to `main` (merged PR) | Plan + apply to AWS |

Authentication uses **GitHub OIDC** — no long-term AWS credentials are stored anywhere. GitHub exchanges a short-lived OIDC token for temporary AWS credentials scoped to the `ai-dp-dev-github-actions` IAM role.

---

## Developer Workflow

```
1. git checkout -b feat/your-change
2. make changes to Terraform/code
3. git add . && git commit -m "feat: description"
4. git push origin feat/your-change
5. Open PR to main on GitHub
      → CI runs automatically (validate + plan)
      → Review plan output posted as PR comment
6. Merge PR
      → Deploy runs automatically (terraform apply)
```

---

## CI Workflow (`ci.yml`)

**Trigger:** Any PR opened or updated targeting `main`

**Concurrency:** One run per PR — new commits cancel the previous in-progress run (prevents stale plan output)

### Step
| Step | Tool | What it does |
|------|------|-------------|
| Checkout | `actions/checkout` | Pulls PR branch code |
| Setup Terraform | `hashicorp/setup-terraform` | Installs Terraform 1.13.0 |
| Setup tflint | `terraform-linters/setup-tflint` | Installs tflint v0.55.0 |
| AWS credentials | `aws-actions/configure-aws-credentials` | OIDC token → short-lived AWS creds |
| Terraform Init | terraform | Initializes backend (S3 state bucket) |
| Format Check | `terraform fmt -check -recursive` | Fails if any `.tf` file is not formatted |
| Validate | `terraform validate` | Checks configuration is syntactically valid |
| tflint | tflint | Lints for AWS provider best practices |
| tfsec | tfsec | Static security analysis (MEDIUM+ severity) |
| Plan | `terraform plan -out=tfplan` | Shows what AWS changes would occur |
| Post plan to PR | `actions/github-script` | Posts plan output as a PR comment |

**Output:** Plan output appears as a comment on the PR before merge.

---

## Deploy Workflow (`deploy.yml`)

**Trigger:** Push to `main` (i.e. every merged PR)

**Concurrency:** Single `deploy-dev` group, `cancel-in-progress: false` — a running apply is never cancelled to prevent partial state.

**Environment:** `dev` — enables GitHub Environment protection rules (required reviewers if configured).

### Steps

| Step | Tool | What it does |
|------|------|-------------|
| Checkout | `actions/checkout` | Pulls main branch code |
| Setup Terraform | `hashicorp/setup-terraform` | Installs Terraform 1.13.0 |
| AWS credentials | `aws-actions/configure-aws-credentials` | OIDC token → short-lived AWS creds |
| Terraform Init | terraform | Initializes backend |
| Plan | `terraform plan -out=tfplan` | Generates plan saved to file |
| Post plan to summary | bash | Writes plan output to Actions job summary |
| Apply | `terraform apply -auto-approve tfplan` | Applies the saved plan to AWS |

**Output:** Plan summary visible in the Actions job summary tab. AWS resources created/modified/destroyed as defined in Terraform.

---

## Authentication — GitHub OIDC

No AWS access keys are stored in GitHub. Instead:

1. GitHub generates a short-lived OIDC JWT for the workflow run
2. AWS STS exchanges it for temporary credentials (1-hour expiry)
3. Credentials are scoped to the `ai-dp-dev-github-actions` IAM role

**IAM Role:** `arn:aws:iam::<ACCOUNT_ID>:role/ai-dp-dev-github-actions`
**Trust policy scope:** `repo:CloudMikey/ai-dp:*` (any branch, tag, or PR in this repo)
**Role managed in Terraform:** `envs/dev/cicd.tf`
**Permission policy managed in the AWS Console** (inline policy `ai-dp-dev-terraform-policy`), on purpose, to get hands-on with IAM there. It can't be reviewed or recreated from this repo.

### Required GitHub configuration

| Type | Name | Value |
|------|------|-------|
| Variable | `AWS_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/ai-dp-dev-github-actions` |
| Secret | `ALARM_EMAIL` | Email address for CloudWatch alarm SNS notifications |

---

## GitHub Environment

The `dev` environment is configured in GitHub repo Settings → Environments.

- Referenced in `deploy.yml` via `environment: dev`
- Enables deployment protection rules (optional required reviewers)
- Provides deployment history and audit trail in the GitHub UI

---

## Backend Configuration

Both workflows initialize Terraform with the same backend used locally:

```
Bucket:  tf-state-aidp      (us-west-1)
Key:     envs/dev/terraform.tfstate
Locking: native S3 locking (use_lockfile = true, no DynamoDB needed)
```

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| CI fails on `fmt` | File not formatted | Run `terraform fmt -recursive` locally before pushing |
| OIDC auth fails | `AWS_ROLE_ARN` variable not set | Add it in repo Settings → Variables |
| Plan fails with `Error acquiring state lock` | Another workflow holds the lock | Wait for the other run to complete |
| Apply fails mid-run | Terraform error or AWS API issue | Check the Actions log; state may be partially applied — run `terraform plan` locally to assess |
| tfsec fails | New resource with security finding | Fix the issue or add a `#tfsec:ignore` comment with justification |
