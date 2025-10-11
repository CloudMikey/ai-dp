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
    ┌────────────┐          ┌──────────────┐
    │  Kinesis   │          │ EventBridge  │
    │  Streams   │          │    Rule      │
    └─────┬──────┘          └──────┬───────┘
          │                        │
          v                        │
    ┌──────────────┐               │
    │  ETL Lambda  │◄──────────────┘
    │  (Normalize) │
    └──────┬───────┘
           │
           v
    ┌────────────────────┐
    │  S3 Data Lake      │
    │  (raw/ layer)      │
    └──────┬─────────────┘
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
| **AI/ML** | Comprehend, SageMaker, Rekognition |
| **Storage** | S3 (Data Lake), DynamoDB |
| **Analytics** | Glue, Athena, QuickSight |
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
│   ├── data_lake/           # S3 buckets (raw/processed/curated)
│   ├── ingestion_stream/    # API Gateway, Kinesis, EventBridge
│   ├── step_functions/      # Orchestration state machine
│   ├── ai_enrichment/       # Comprehend, Rekognition, SageMaker
│   ├── hot_store/           # DynamoDB tables
│   ├── analytics/           # Glue crawler, Athena
│   └── observability/       # CloudWatch dashboards, alarms, DLQs
├── lambdas/             # Python Lambda function code
│   ├── etl/            # Kinesis consumer (normalize & write to S3)
│   ├── merge/          # Merge AI outputs, write to storage
│   └── replay/         # DLQ replay utility
├── scripts/            # Utility scripts for testing/operations
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

**Current Phase**: Phase 0-1 (Bootstrap & Initial Setup)

This project is in active development. See [`docs/roadmap.md`](docs/roadmap.md) for detailed implementation phases and completion criteria.

### Completed
- Repository structure
- Configuration files (.gitignore, .editorconfig)
- Documentation framework

### In Progress
- Terraform backend setup
- AWS OIDC configuration
- CI/CD pipeline

### Planned
- Data Lake module
- Ingestion pipelines (batch + streaming)
- AI enrichment orchestration
- Analytics layer
- Security hardening

## Documentation

- **[Project Overview](docs/ai-dp%20overview%20notion.md)**: Comprehensive architecture guide
- **[Roadmap](docs/roadmap.md)**: Implementation phases and tasks
- **[CLAUDE.md](CLAUDE.md)**: Development standards and patterns
- **[Error Log](docs/errorlog.md)**: Common issues and solutions

## Design Principles

1. **NO HARDCODING**: All solutions are generic and pattern-based
2. **ROOT CAUSE, NOT BANDAID**: Fix underlying structural issues
3. **DATA INTEGRITY**: Use consistent, authoritative data sources
4. **SECURITY-FIRST**: OIDC authentication, least-privilege IAM, no long-term credentials
5. **ENVIRONMENT ISOLATION**: Strict separation between dev/staging/prod

## CI/CD Pipeline

The project uses GitHub Actions with AWS OIDC for secure, automated deployments:

- **CI Workflow** (Pull Requests): Terraform fmt, validate, plan, security scanning
- **Deploy Workflow** (Main Branch): Automated deployment with approval gates
- **Environment Promotion**: dev → staging → production

## Cost Optimization

- S3 lifecycle policies for data archival
- DynamoDB on-demand pricing (or provisioned with auto-scaling)
- Lambda reserved concurrency for predictable workloads
- Kinesis shard scaling based on traffic patterns
- SageMaker endpoint auto-scaling

## Security

- All data encrypted at rest (S3, DynamoDB)
- TLS for data in transit
- IAM least-privilege roles
- VPC endpoints for AWS service access
- DLQs for error handling
- CloudWatch alarms for anomaly detection

## Contributing

This is a personal portfolio project. Contributions, suggestions, and feedback are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact

**Project Author**: [Your Name]
- GitHub: [@your-username](https://github.com/your-username)
- LinkedIn: [Your Profile](https://linkedin.com/in/your-profile)
- Email: your.email@example.com

## Acknowledgments

- AWS Architecture Center for best practices
- HashiCorp Terraform documentation
- AWS Serverless examples and patterns

---

**Built with AWS, Terraform, and Python**
