# AI-Powered Serverless Data Pipeline

![Status](https://img.shields.io/badge/status-in%20development-yellow)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.11.0-blue)
![AWS](https://img.shields.io/badge/AWS-serverless-orange)
![License](https://img.shields.io/badge/license-MIT-green)

A production-grade, serverless data pipeline built on AWS that ingests, enriches, and analyzes data using AI/ML services. This project demonstrates modern cloud architecture patterns, Infrastructure as Code (IaC), and AI/ML integration.

## Overview

This pipeline processes both **batch** and **streaming** data, enriching it with AWS AI services (Comprehend, SageMaker, Rekognition), and provides analytics through a dual storage strategy:
- **Hot Storage**: DynamoDB for low-latency recent data queries
- **Historical Storage**: S3 Data Lake for long-term analytics with Athena

### Key Features

- **Multi-Modal Ingestion**: REST API (streaming) + S3 batch uploads
- **AI/ML Enrichment**: Sentiment analysis, entity extraction, anomaly detection, image labeling
- **Serverless Architecture**: Zero server management, auto-scaling, pay-per-use
- **Dual Storage Strategy**: Real-time queries (DynamoDB) + Historical analytics (S3 + Athena)
- **Infrastructure as Code**: 100% Terraform-managed, multi-environment support
- **Production-Ready**: Error handling, monitoring, DLQ replay, security best practices
- **CI/CD**: GitHub Actions with OIDC (no long-term credentials)

## Architecture

```
┌─────────────────┐      ┌─────────────────┐
│   API Gateway   │      │   S3 Batch      │
│   (Streaming)   │      │   Upload        │
└────────┬────────┘      └────────┬────────┘
         │                        │
         v                        v
    ┌────────────┐          ┌────────────────────┐
    │  Kinesis   │          │  S3 Data Lake      │
    │  Streams   │          │  (raw/ layer)      │
    └─────┬──────┘          └──────┬─────────────┘
          │                        │
          v                        v
    ┌──────────────┐          ┌──────────────┐
    │  ETL Lambda  │          │ EventBridge  │
    │  (Normalize) │          │    Rule      │
    └──────┬───────┘          └──────┬───────┘
           │                         │
           v                         │
    ┌────────────────────┐           │
    │  S3 Data Lake      │           │
    │  (raw/ layer)      │           │
    └────────────────────┘           │
                                     │
           ┌─────────────────────────┘
           │
           v
    ┌───────────────────────────┐
    │   Step Functions          │
    │   (Orchestration)         │
    └───────┬───────────────────┘
            │
      ┌─────┼─────┬─────────────┐
      │     │     │             │
      v     v     v             v
   ┌────┐ ┌────┐ ┌──────┐  ┌───────────┐
   │Comp│ │Reko│ │Sage- │  │ (Future)  │
   │hend│ │gni-│ │Maker │  │   ...     │
   │    │ │tion│ │      │  │           │
   └──┬─┘ └──┬─┘ └───┬──┘  └─────┬─────┘
      │      │       │           │
      └──────┴───────┴───────────┘
                     │
                     v
              ┌──────────────┐
              │Merge Lambda  │
              └──────┬───────┘
                     │
            ┌────────┴────────┐
            │                 │
            v                 v
    ┌──────────────┐   ┌────────────┐
    │ S3 processed/│   │  DynamoDB  │
    │   curated/   │   │ (Hot Store)│
    └──────┬───────┘   └────────────┘
           │
           v
    ┌────────────────┐
    │ Glue Crawler + │
    │     Athena     │
    └────────────────┘
```


For detailed architecture documentation, see [`docs/ai-dp overview notion.md`](docs/ai-dp%20overview%20notion.md).

## Technology Stack

| Layer | Technologies |
|-------|-------------|
| **Infrastructure** | Terraform >= 1.11.0, AWS |
| **Compute** | Lambda (Python 3.11+), Step Functions |
| **Ingestion** | API Gateway, Kinesis Data Streams, EventBridge |
| **AI/ML** | Comprehend (sentiment, entities) |
| **Storage** | S3 (Data Lake), DynamoDB |
| **Analytics** | Glue, Athena, Chart.js Dashboard |
| **Observability** | CloudWatch, X-Ray, SQS DLQs |
| **CI/CD** | GitHub Actions (OIDC) |

## Repository Structure

```
AI-DP/
├── bootstrap/            # Terraform config for S3 state bucket
├── envs/                 # Environment-specific Terraform configs
│   ├── dev/             # Development environment
│   ├── stg/             # Staging environment
│   └── prod/            # Production environment
├── modules/             # Reusable Terraform modules
│   ├── data_lake/           # S3 buckets (raw/processed/curated) ✅
│   ├── ingestion_stream/    # API Gateway, Kinesis, EventBridge ✅
│   ├── step_functions/      # State machine + Comprehend AI ✅
│   ├── hot_store/           # DynamoDB tables ✅
│   ├── orchestration/       # Merge Lambda ✅
│   ├── analytics/           # Glue crawler, Athena ✅
│   └── observability/       # CloudWatch dashboards, alarms (Phase 9)
├── lambdas/             # Python Lambda function code
│   ├── etl/            # Kinesis consumer (normalize & write to S3)
│   ├── merge/          # Merge AI outputs, write to storage
│   └── replay/         # DLQ replay utility (Phase 9)
├── dashboard/          # Browser-based analytics dashboard ✅
│   ├── index.html     # Main HTML file
│   ├── styles.css     # Dark theme styling
│   └── app.js         # Chart.js + AWS SDK integration
└── docs/               # Project documentation
```

## Quick Start

### Prerequisites

- **Terraform** >= 1.11.0 ([Download](https://www.terraform.io/downloads))
- **AWS CLI** configured with credentials
- **Python** 3.11+ (for Lambda development)
- **Git**

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/AI-DP.git
cd AI-DP
```

### 2. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Key, and default region
```

### 3. Bootstrap Terraform Backend (First-Time Setup)

Create the S3 bucket for Terraform state:

```powershell
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply
```

This creates an S3 bucket with:
- Versioning enabled
- Encryption at rest (SSE-S3)
- Native state locking (Terraform >= 1.11.0)

### 4. Initialize Development Environment

```powershell
terraform -chdir=envs/dev init
terraform -chdir=envs/dev plan
terraform -chdir=envs/dev apply
```

### 5. Deploy to Staging/Production

```powershell
# Staging
terraform -chdir=envs/stg init
terraform -chdir=envs/stg apply

# Production
terraform -chdir=envs/prod init
terraform -chdir=envs/prod apply
```

## Development Workflow

### Terraform Commands

```powershell
# Format Terraform files
terraform -chdir=envs/dev fmt -recursive

# Validate configuration
terraform -chdir=envs/dev validate

# Plan changes
terraform -chdir=envs/dev plan -out=plan.out

# Apply changes
terraform -chdir=envs/dev apply plan.out

# Destroy resources (use with caution!)
terraform -chdir=envs/dev destroy
```

### Python Lambda Development

```powershell
# Navigate to Lambda function directory
cd lambdas/etl

# Create virtual environment
python -m venv venv
.\venv\Scripts\activate  # Windows
source venv/bin/activate # Linux/Mac

# Install dependencies
pip install -r requirements.txt

# Run tests (when implemented)
pytest
```

## Testing

```powershell
# Unit tests (when implemented)
pytest lambdas/etl/
pytest lambdas/merge/

# Integration tests
# See scripts/ for test utilities
```

## Project Status

**Current Phase**: Phase 9 (67%) + Phase 10 Task 1 ✅ — CI/CD OIDC Role Setup Complete
**Overall Progress**: ~93% (Phase 10 Task 1 complete — 2026-03-22)

This project is in active development. See [`docs/roadmap.md`](docs/roadmap.md) for detailed implementation phases and completion criteria.

### ✅ Completed Phases

**Phase 0: Bootstrap Infrastructure**
- S3 state bucket with native locking (Terraform >= 1.11.0)
- All environments initialized (dev, stg, prod)

**Phase 1: Data Lake Foundation**
- S3 bucket: `ai-dp-data-lake-dev-us-west-2`
- Three-layer architecture (raw/processed/curated)
- Lifecycle policies, versioning, encryption

**Phase 2: Streaming Ingestion**
- API Gateway HTTP API + Kinesis Data Streams
- ETL Lambda function (Python 3.11)
- Idempotent writes (Kinesis sequence numbers as S3 filenames)
- End-to-end tested: API → Kinesis → Lambda → S3

**Phase 3: Batch Ingestion EventBridge**
- EventBridge rule detects S3 uploads to raw/ layer
- Filtered event pattern (prevents infinite loops)

**Phase 4: Step Functions & EventBridge Wiring**
- State machine deployed: `ai-dp-dev-orchestrator`
- EventBridge → Step Functions integration
- End-to-end batch path tested and verified

**Phase 5: DynamoDB Hot Store**
- DynamoDB table deployed: `ai-dp-dev-enriched-data`
- On-demand billing, TTL (30 days), PITR enabled
- GSI for time-based queries

**Phase 6: AI Enrichment Services**
- AWS Comprehend integrated (sentiment + entity detection)
- Parallel execution in Step Functions
- Real-time AI enrichment operational

**Phase 7: Merge Lambda & Complete Orchestration**
- Merge Lambda deployed: `ai-dp-dev-merge`
- Dual storage strategy: S3 processed/ + DynamoDB
- End-to-end pipeline fully operational (streaming + batch)

**Phase 8: Analytics & Query Layer**
- Glue Crawler + Athena: SQL queries on S3 data lake
- Browser-based dashboard (HTML/CSS/JS + Chart.js)
- Three-tier data strategy: Curated S3 (~100ms) + DynamoDB (~50ms) + Athena (~3s)
- Optimized dashboard: Sentiment chart from pre-aggregated Curated S3 for instant loading
- Responsive design: Real-time metrics, sentiment charts, entity analysis
- Zero dependencies: Runs directly from file system or S3 static hosting

**Phase 9: Production Hardening** (67% — 6/9 tasks complete)
- ✅ Lambda unit tests (33 tests, 96% coverage)
- ✅ Load testing (1000 events, 0% errors)
- ✅ CloudWatch Dashboard (8 widgets) + 6 Alarms + SNS
- ✅ Security Review (IAM audit, KMS, tfsec — 0 critical findings)
- ✅ Cost Optimization ($12/month actual, 76% under $50 budget)
- ⏳ Architecture Docs, Operational Runbooks, Staging

**Phase 10: CI/CD Pipeline** (17% — 1/6 tasks complete)
- ✅ **Task 1:** GitHub Actions OIDC role (`ai-dp-dev-github-actions`) — least-privilege IAM, Terraform-managed
- ⏳ Tasks 2-6: CI workflow, Deploy workflow, Environment protection, Testing, Docs

### 📋 Remaining

- Phase 9 Tasks 7-9 (Architecture Docs, Runbooks, Staging)
- Phase 10 Tasks 2-6 (CI/CD Workflows)

## Documentation

- **[Project Overview](docs/ai-dp%20overview%20notion.md)**: Comprehensive architecture guide
- **[Interview Walkthrough](docs/explained.md)**: How to explain this project in interviews
- **[Data Flow](docs/data_flow.md)**: End-to-end data flow documentation
- **[Roadmap](docs/roadmap.md)**: Implementation phases and tasks
- **[CLAUDE.md](CLAUDE.md)**: Development standards and patterns
- **[Error Log](docs/errorlog.md)**: Common issues and solutions

## Design Principles

1. **NO HARDCODING**: All solutions are generic and pattern-based
2. **ROOT CAUSE, NOT BANDAID**: Fix underlying structural issues
3. **DATA INTEGRITY**: Use consistent, authoritative data sources
4. **SECURITY-FIRST**: OIDC authentication, least-privilege IAM, no long-term credentials
5. **ENVIRONMENT ISOLATION**: Strict separation between dev/staging/prod

## CI/CD Pipeline (Phase 10)

> **Note:** CI/CD deferred to Phase 10 after all infrastructure is built and proven working.

**Planned implementation:**
- **CI Workflow** (Pull Requests): Terraform fmt, validate, plan, security scanning
- **Deploy Workflow** (Main Branch): Automated deployment with approval gates
- **Environment Promotion**: dev → staging → production
- **OIDC Authentication**: No long-term credentials

## Cost Optimization

- S3 lifecycle policies (IA → Glacier → expiration)
- DynamoDB on-demand pricing + TTL auto-cleanup
- Athena partition pruning (90%+ cost reduction)
- Kinesis single-shard for dev (scale as needed)
- Separate Athena results bucket with 7-day lifecycle

## Security

- All data encrypted at rest (S3 SSE-AES256, DynamoDB)
- TLS/HTTPS enforced via bucket policies
- IAM least-privilege roles (scoped to specific prefixes)
- Public access blocked on all S3 buckets
- SQS DLQs for error handling and retry
- Point-in-time recovery enabled on DynamoDB

## Contributing

This is a personal portfolio project. Contributions, suggestions, and feedback are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- AWS Architecture Center for best practices
- HashiCorp Terraform documentation
- AWS Serverless examples and patterns

---

**Built with AWS, Terraform, and Python** | **Portfolio Project for Cloud Engineering Roles**
