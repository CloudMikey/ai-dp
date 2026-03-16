# AI-Powered Serverless Data Pipeline - Project Overview

## Project Type
Portfolio project for entry-level to intermediate cloud engineering roles. Demonstrates AWS serverless architecture with AI/ML enrichment, managed entirely with Terraform IaC.

## Purpose
Ingests batch and streaming data, enriches it with AWS AI services (Comprehend), and provides analytics through dual storage (DynamoDB hot store + S3 data lake).

## Core Data Flow
1. **Streaming**: API Gateway → Kinesis Data Streams → ETL Lambda → S3 `raw/`
2. **Batch**: S3 uploads → EventBridge → Step Functions
3. **Orchestration**: Step Functions orchestrates AI enrichment (Comprehend)
4. **Merge & Store**: Merge Lambda → S3 `processed/` + DynamoDB (30-day TTL)
5. **Analytics**: Glue Crawler → Athena SQL + static HTML/JS dashboard (Chart.js)

## Tech Stack
- **IaC**: Terraform >= 1.11.0, S3 backend with native locking (`use_lockfile = true`)
- **Compute**: AWS Lambda (Python 3.11), Step Functions, EventBridge
- **Ingestion**: API Gateway (HTTP API), Kinesis Data Streams
- **Storage**: S3 (raw/processed/curated), DynamoDB (on-demand)
- **AI/ML**: Amazon Comprehend (sentiment + entity extraction)
- **Analytics**: Glue Crawler, Athena, static dashboard (Vanilla JS + Chart.js v4.4.0 + AWS SDK v2)
- **Observability**: CloudWatch Dashboard (8 widgets), 6 alarms, SNS, SQS DLQs, X-Ray

## Current Status (~92% Complete)
- **Phases 0-8**: Complete (bootstrap through analytics/dashboard)
- **Phase 9**: 6/9 tasks done (tests, load test, dashboard, alarms, security, cost review)
  - Remaining: Architecture docs, runbooks, staging deployment
- **Phase 10**: CI/CD (deferred)

## Deployed Resources (dev, us-west-2)
- State bucket: `tf-state-aidp` (us-west-1)
- Data lake: `ai-dp-data-lake-dev-us-west-2`
- Kinesis: `ai-dp-dev-ingestion-stream` (KMS encrypted)
- API Gateway: `https://pvqb2gzg7i.execute-api.us-west-2.amazonaws.com/ingest`
- Step Functions: `ai-dp-dev-orchestrator`
- DynamoDB: `ai-dp-dev-enriched-data`
- Glue DB: `ai-dp-dev-analytics` | Athena: `ai-dp-dev-workgroup`
- CloudWatch Dashboard: `ai-dp-dev-operations`
- AWS Budget: `ai-dp-dev-monthly-budget` ($50/month, actual ~$12/month)
