# AI-Powered Serverless Data Pipeline - Project Overview

## Project Type
This is an **AI-Powered Serverless Data Pipeline** built on AWS, managed entirely with Terraform Infrastructure as Code. It's a **portfolio project** designed for entry-level to intermediate cloud engineering roles.

## High-Level Architecture

### Purpose
Ingests both batch and streaming data, enriches it with AWS AI/ML services (Comprehend), and provides actionable insights through dual storage strategy (DynamoDB hot store + S3 data lake).

### Core Data Flow
1. **Ingestion Layer**: 
   - Streaming: API Gateway → Kinesis Data Streams → ETL Lambda → S3 `raw/`
   - Batch: S3 uploads → EventBridge → Step Functions
2. **Orchestration**: Step Functions orchestrates AI enrichment tasks
3. **AI Enrichment**: Amazon Comprehend (sentiment analysis + entity extraction) running in parallel
4. **Merge & Store**: Merge Lambda combines AI outputs → writes to:
   - S3 `processed/` (historical data lake with date partitioning)
   - DynamoDB (hot store for low-latency queries, 30-day TTL)
5. **Analytics**: 
   - Glue Crawler catalogs `processed/` data → Athena SQL queries
   - Static HTML/JS dashboard with Chart.js visualizations

### Error Handling Pattern
- All Lambdas configured with SQS Dead Letter Queues (DLQs)
- CloudWatch Logs for all components
- Step Functions retry logic with catch blocks
- Idempotent S3 writes using Kinesis sequence numbers

## Technology Stack

### Infrastructure & IaC
- **Terraform**: >= 1.11.0 with S3 backend using native locking (`use_lockfile = true`)
- **Environments**: dev, stg, prod with separate state files

### AWS Services
- **Compute**: Lambda (Python 3.11), Step Functions, EventBridge
- **Data Ingestion**: API Gateway (HTTP API), Kinesis Data Streams
- **Storage**: S3 (three-tier data lake), DynamoDB (on-demand billing)
- **AI/ML**: Amazon Comprehend (sentiment + entities)
- **Analytics**: Glue Crawler, Athena, static dashboard

### Dashboard
- **Tech**: Vanilla HTML/CSS/JavaScript + Chart.js v4.4.0 + AWS SDK for JavaScript v2
- **Features**: 
  - Sentiment pie chart (**Curated S3** - pre-aggregated, instant ~100ms)
  - Entity doughnut chart (Athena with UNNEST - demonstrates SQL skills)
  - 5 real-time metrics cards (DynamoDB): Total, Positive, Neutral, Negative, Mixed
  - Recent events table (20 most recent from DynamoDB)
  - Pipeline status: Total processed (**Curated S3**), last record time, DLQ health check
  - Auto-refresh (60s), parallel queries
- **Optimized Data Sources** (2026-01-24):
  | Feature | Before | After | Why |
  |---------|--------|-------|-----|
  | Sentiment Chart | Athena (~3s) | Curated S3 (~100ms) | Pre-aggregated counts, instant |
  | Total Processed | Athena (~3s) | Curated S3 (~100ms) | Pre-calculated by Merge Lambda |
  | Entity Chart | Athena (~3s) | Athena (~3s) | Kept - demonstrates UNNEST SQL skill |
  | Metrics Cards | DynamoDB (~50ms) | DynamoDB (~50ms) | Real-time, last 30 days |
- **Location**: `dashboard/` directory (index.html, styles.css, app.js, config.js, README.md)
- **Auth**: Local credentials in `config.js` (gitignored) - for demo only; production would use Cognito
- **Design**: Modern dark theme, responsive layout (desktop/tablet/mobile)
- **Deployment**: Zero dependencies - runs from file system or S3 static hosting

## Current Project Status

**90% Complete (9 of 10 phases)**

✅ **Completed:**
- Phase 0: Bootstrap (S3 state bucket)
- Phase 1: Data Lake (S3 three-tier)
- Phase 2: Streaming Ingestion (API → Kinesis → Lambda → S3)
- Phase 3: Batch Ingestion (S3 → EventBridge)
- Phase 4: Step Functions Orchestration
- Phase 5: DynamoDB Hot Store
- Phase 6: AI Enrichment (Comprehend)
- Phase 7: Merge Lambda & Complete Pipeline
- Phase 8: Analytics & Dashboard (Glue, Athena, Chart.js)

🔄 **Next:** Phase 9 (Production Hardening), Phase 10 (CI/CD)

## Key Design Principles

- **Portfolio-appropriate**: Simple enough to explain in interviews, complex enough to demonstrate skills
- **Serverless-first**: No EC2, fully managed services
- **Security-first**: Least-privilege IAM, encryption at rest/transit
- **Cost-optimized**: On-demand billing, lifecycle policies, partition pruning
- **Production-ready patterns**: DLQs, retries, monitoring from day one
