# AI-Powered Serverless Data Pipeline

## Project overview

---

### 🚀 Final Project Overview: AI-Powered Serverless Data Pipeline 

### 🎯 **Project Goal**

Design and deploy a **serverless data pipeline** that ingests both batch and real-time data, processes it with AI/ML services, and delivers actionable insights through dashboards — all while ensuring scalability, reliability, and cost efficiency.

---

## 🔧 **Core Components**

1. **Data Ingestion**
    - **Batch uploads** via S3 (CSV/JSON).
    - **Real-time events** via API Gateway → Kinesis Data Streams.
2. **Data Processing & AI Integration**
    - **Step Functions** orchestrate multiple tasks.
    - **Text analytics** (sentiment & entity extraction with Comprehend).
    - **Optional image labeling** (Rekognition).
    - **Anomaly detection** using a SageMaker real-time endpoint.
3. **Data Storage & Querying**
    - **DynamoDB** for hot data and real-time lookups.
    - **S3 Data Lake** with raw, processed, and curated partitions.
    - **Glue + Athena** for ad-hoc SQL queries over processed data.
4. **Analytics & Insights**
    - **QuickSight dashboard** or React web app for visualization.
    - Provides live trends, predictions, and anomaly alerts.
5. **Reliability & Monitoring**
    - **CloudWatch Dashboards + Alarms** for pipeline health.
    - **SQS Dead Letter Queues (DLQ)** for failed message recovery.
    - Logging and distributed tracing with **CloudWatch + X-Ray**.

---

### 🛠️ **Tech Stack**

- **Compute & Orchestration**
    - AWS Lambda
    - AWS Step Functions
    - Amazon EventBridge
- **Data Ingestion**
    - Amazon API Gateway
    - Amazon Kinesis Data Streams
- **Storage & Query**
    - Amazon S3 (raw/processed/curated layers)
    - Amazon DynamoDB
    - AWS Glue
    - Amazon Athena
- **AI/ML Services**
    - Amazon Comprehend (text analytics)
    - Amazon Rekognition (image labeling – optional)
    - Amazon SageMaker (real-time inference endpoint)
- **Analytics & Frontend**
    - Amazon QuickSight (dashboards)
    - React + AWS Amplify (optional web UI)
- **Monitoring & Reliability**
    - Amazon CloudWatch (logs, metrics, dashboards)
    - AWS X-Ray (tracing)
    - Amazon SQS (dead letter queues)
- **Other Tools**
    - Terraform (Infrastructure as Code)
    - GitHub Actions (CI/CD automation)

---

### 📊 **Key Capabilities**

- **Hybrid ingestion:** supports both streaming and batch data.
- **AI/ML enrichment:** integrates AWS AI services and custom ML endpoints.
- **Dual storage strategy:** real-time (DynamoDB) + historical (S3/Athena).
- **Production-ready reliability:** DLQs, alarms, and replay mechanisms.
- **Actionable insights:** dashboards and alerts for end-users.

---

### 🌟 **Portfolio Value**

- Demonstrates **serverless architecture design** across multiple AWS services.
- Proves ability to build **data engineering + AI/ML integration** pipelines.
- Highlights **MLOps practices** with SageMaker endpoints in production.
- Shows **production-readiness** (monitoring, error handling, scalability).
- Strong differentiator — far beyond “hello world” cloud projects.

---

---

---

---

## Architecture Overview

---

### 1) System Architecture (at a glance)

```
[Clients/Producers]
    |  (HTTP events, files)
    v
API Gateway  ──►  Kinesis (stream)  ──► Lambda(ETL) ──► S3 raw/
                            ▲
S3 (batch uploads) ─────────┘
         │  (EventBridge notify)
         v
               Step Functions (orchestrator)
        ┌───────────────┬─────────────────┬────────────────────┐
        │               │                 │                    │
   Comprehend       Rekognition*     SageMaker RT         (Retries/Errors)
  (text enrich)   (image labels)     (anomaly score)      ──► SQS DLQ (replay)
        └───────────────┴─────────────────┴────────────────────┘
                              |
                              v
             DynamoDB (hot view)     S3 processed/curated (history)
                              |                 |
                              |           Glue Crawler
                              |                 v
                              |              Athena (SQL)
                              |                 |
                              └────────►  QuickSight / React UI

```

- Rekognition optional (feature-flagged).

---

### 2) Key Components

- **Ingestion:** API Gateway (real-time) → Kinesis; S3 (batch) → EventBridge.
- **Processing & Orchestration:** Lambda ETL; Step Functions fan-out to Comprehend / Rekognition* / SageMaker endpoint; merge and write results.
- **Storage:**
    - **Hot:** DynamoDB for low-latency lookups.
    - **Historical:** S3 (`raw/`, `processed/`, `curated/`) + Glue + Athena for ad-hoc analytics.
- **Analytics:** QuickSight or React + Amplify dashboard.
- **Reliability:** SQS DLQs, idempotent Lambdas, CloudWatch Alarms/Dashboards, X-Ray traces.
- **CI/CD & IaC:** Terraform (S3 backend with **native lockfile**, no DynamoDB), GitHub Actions with **OIDC** to assume AWS roles.

---

### 3) Environments & Promotion

- **envs:** `dev → stg → prod` with separate state keys, roles, and parameters.
- **GitHub Actions:** PRs run `fmt/validate/plan`; protected applies with manual approvals promote to higher envs.

---

### 4) Terraform Backend (S3 with native lock)

```hcl
# envs/dev/backend.tf
terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "tf-state-<acct>-<region>"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-west-1"
    encrypt      = true
    use_lockfile = true   # Native S3 state lock; no DynamoDB table
  }
}

```

---

### 5) Directory Skeleton

> Modular, environment-scoped, CI-friendly. Adjust names to taste.
> 

```
repo-root/
├─ README.md
├─ .editorconfig
├─ .gitignore
├─ .github/
│  └─ workflows/
│     ├─ ci.yml                 # PR: fmt/validate/tflint/tfsec/plan
│     └─ deploy.yml             # env deploy via OIDC assume-role
├─ scripts/
│  ├─ bootstrap-remote-state.ps1     # create state bucket, enable versioning
│  ├─ dlq-replay.ps1                  # SQS DLQ replay helper
│  └─ load-test-kinesis.ps1           # sample event generator
├─ envs/
│  ├─ dev/
│  │  ├─ backend.tf              # S3 backend + use_lockfile
│  │  ├─ providers.tf
│  │  ├─ variables.tf
│  │  ├─ terraform.tfvars        # dev values (names, sizes, flags)
│  │  └─ main.tf                 # root stack wiring modules/*
│  ├─ stg/
│  │  ├─ backend.tf
│  │  ├─ providers.tf
│  │  ├─ terraform.tfvars
│  │  └─ main.tf
│  └─ prod/
│     ├─ backend.tf
│     ├─ providers.tf
│     ├─ terraform.tfvars
│     └─ main.tf
├─ modules/
│  ├─ data_lake/
│  │  ├─ main.tf      # S3 buckets (raw/processed/curated), lifecycle, encryption
│  │  ├─ outputs.tf
│  │  └─ variables.tf
│  ├─ ingestion_stream/
│  │  ├─ main.tf      # API Gateway, Kinesis, Lambda(consumer), IAM, EventBridge rules
│  │  ├─ outputs.tf
│  │  └─ variables.tf
│  ├─ step_functions/
│  │  ├─ main.tf      # State machine, ASL JSON, CloudWatch logging, retries
│  │  ├─ statemachine.asl.json
│  │  ├─ outputs.tf
│  │  └─ variables.tf
│  ├─ ai_enrichment/
│  │  ├─ main.tf      # Comprehend/Rekognition toggles, SageMaker endpoint
│  │  ├─ outputs.tf
│  │  └─ variables.tf
│  ├─ hot_store/
│  │  ├─ main.tf      # DynamoDB table(s), GSIs, TTL
│  │  ├─ outputs.tf
│  │  └─ variables.tf
│  ├─ analytics/
│  │  ├─ main.tf      # Glue crawler, Athena db/tables, (optional) QuickSight skeleton
│  │  ├─ outputs.tf
│  │  └─ variables.tf
│  └─ observability/
│     ├─ main.tf      # CloudWatch dashboards/alarms, X-Ray, SQS DLQs, IAM perms
│     ├─ outputs.tf
│     └─ variables.tf
├─ lambdas/
│  ├─ etl/
│  │  ├─ app.py               # Kinesis consumer (validate/normalize/write raw)
│  │  └─ requirements.txt
│  ├─ merge/
│  │  ├─ app.py               # merges AI outputs, writes processed + DynamoDB
│  │  └─ requirements.txt
│  └─ replay/
│     ├─ app.py               # DLQ replay utility (optional infra-triggered)
│     └─ requirements.txt
└─ app/
   ├─ web/                    # optional React dashboard (Amplify)
   └─ notebooks/              # (optional) experiments, Athena queries, docs

```

---

### 6) Root `main.tf` (wiring example)

```hcl
module "data_lake" {
  source           = "../modules/data_lake"
  bucket_name_root = var.bucket_name_root
  enable_kms       = true
  tags             = var.tags
}

module "ingestion_stream" {
  source                 = "../modules/ingestion_stream"
  api_name               = "${var.project}-ingest"
  kinesis_shards         = var.kinesis_shards
  raw_bucket_arn         = module.data_lake.raw_bucket_arn
  eventbridge_bus_name   = var.eventbridge_bus_name
  feature_rekognition_on = var.feature_rekognition_on
  tags                   = var.tags
}

module "step_functions" {
  source              = "../modules/step_functions"
  state_machine_name  = "${var.project}-enrich"
  log_level           = "ALL"
  tags                = var.tags
}

module "ai_enrichment" {
  source                 = "../modules/ai_enrichment"
  feature_rekognition_on = var.feature_rekognition_on
  sagemaker_instance     = var.sagemaker_instance
  tags                   = var.tags
}

module "hot_store" {
  source     = "../modules/hot_store"
  table_name = "${var.project}-hot"
  tags       = var.tags
}

module "analytics" {
  source            = "../modules/analytics"
  glue_db_name      = var.glue_db_name
  processed_bucket  = module.data_lake.processed_bucket
  curated_bucket    = module.data_lake.curated_bucket
  create_quicksight = var.create_quicksight
  tags              = var.tags
}

module "observability" {
  source                 = "../modules/observability"
  alarm_email            = var.alarm_email
  enable_xray            = true
  enable_dlq_dashboards  = true
  tags                   = var.tags
}

```

---

### 7) GitHub Actions (OIDC) — minimal skeleton

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
    paths: [ "envs/**", "modules/**", "lambdas/**" ]
jobs:
  plan-dev:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<acct>:role/gh-oidc-deploy-dev
          aws-region: us-west-1
      - run: terraform -chdir=envs/dev init
      - run: terraform -chdir=envs/dev fmt -check
      - run: terraform -chdir=envs/dev validate
      - run: terraform -chdir=envs/dev plan -input=false

```

---

### 8) Parameters & Feature Flags (examples)

```hcl
# envs/dev/terraform.tfvars
project                = "serverless-ai-pipeline"
region                 = "us-west-1"
bucket_name_root       = "dlk-mvpplus-dev"
kinesis_shards         = 1
glue_db_name           = "dlk_processed_dev"
sagemaker_instance     = "ml.t2.medium"
feature_rekognition_on = false
create_quicksight      = false
alarm_email            = "alerts@example.com"
tags = {
  Project = "ServerlessAIMVPPlus"
  Env     = "dev"
  Owner   = "you"
}

```

---