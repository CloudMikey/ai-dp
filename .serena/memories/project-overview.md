# AI-Powered Serverless Data Pipeline - Project Overview

## Project Type
This is an **AI-Powered Serverless Data Pipeline** built on AWS, managed entirely with Terraform Infrastructure as Code.

## High-Level Architecture

### Purpose
Ingests both batch and streaming data, enriches it with AWS AI/ML services, and provides actionable insights through dual storage strategy (hot + historical).

### Core Data Flow
1. **Ingestion Layer**: API Gateway → Kinesis Data Streams (real-time) OR S3 uploads → EventBridge (batch)
2. **ETL Layer**: Lambda consumes Kinesis → validates/normalizes → writes to S3 `raw/`
3. **Orchestration**: Step Functions orchestrates parallel AI enrichment tasks
4. **AI Enrichment**: 
   - Amazon Comprehend (sentiment analysis, entity extraction)
   - SageMaker real-time endpoint (anomaly detection)
   - Amazon Rekognition (optional, feature-flagged for image labeling)
5. **Merge & Store**: Lambda combines AI outputs → writes to:
   - S3 `processed/` and `curated/` (historical data lake)
   - DynamoDB (hot store for low-latency queries)
6. **Analytics**: Glue crawler catalogs S3 data → Athena queries → QuickSight/React dashboards

### Error Handling Pattern
- All Lambdas configured with SQS Dead Letter Queues (DLQs)
- CloudWatch alarms monitor DLQ depth
- Dedicated replay Lambda processes failed messages
- X-Ray tracing for distributed debugging

## Technology Stack

### Infrastructure & IaC
- **Terraform**: >= 1.11.0 with S3 backend using native locking (`use_lockfile = true`, no DynamoDB needed)
- **Environments**: dev, stg, prod with separate state files and IAM roles

### AWS Services
- **Compute**: Lambda, Step Functions, EventBridge
- **Data Ingestion**: API Gateway (HTTP API), Kinesis Data Streams
- **Storage**: S3 (multi-tier data lake), DynamoDB
- **AI/ML**: Comprehend, SageMaker, Rekognition (optional)
- **Analytics**: Glue, Athena, QuickSight
- **Observability**: CloudWatch Logs/Dashboards/Alarms, X-Ray

### CI/CD (Planned)
- GitHub Actions with OIDC authentication (no long-term AWS credentials)
- Automated workflows: terraform fmt/validate/plan on PRs, apply on main branch
- Environment promotion with manual approval gates

## Current Project Status
The project is in **early development** (Phase 0-1 of roadmap). Directory structure exists but most modules and Lambda functions are not yet implemented. See `docs/roadmap.md` for detailed implementation phases.

## Key Design Principles
- **Serverless-first**: No EC2, fully managed services
- **Security-first**: OIDC auth, least-privilege IAM, encryption at rest/transit
- **Cost-optimized**: Feature flags, lifecycle policies, on-demand scaling
- **Production-ready**: DLQs, retries, monitoring, alarms from day one