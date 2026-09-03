# AI-Powered Serverless Data Pipeline - Project Overview

## Project Type
Portfolio project for entry-level to intermediate cloud engineering roles. Demonstrates AWS serverless architecture with AI/ML enrichment, managed entirely with Terraform IaC.

## Purpose
Ingests batch and streaming data, enriches it with AWS AI services (Comprehend), and provides analytics through dual storage (DynamoDB hot store + S3 data lake).

## Core Data Flow
1. **Streaming**: API Gateway → Kinesis Data Streams → ETL Lambda → S3 `raw/`
2. **Batch**: S3 uploads → EventBridge → Step Functions. Step Functions passes the **whole file body** to Comprehend (no JSON parsing), so batch inputs are plain `.txt`, one document per file, under 5,000 bytes (`DetectSentiment`'s cap). 1 file = 1 record = 1 sentiment; `--recursive` uploads fire one concurrent execution per object.
3. **Orchestration**: Step Functions orchestrates AI enrichment (Comprehend)
4. **Merge & Store**: Merge Lambda → S3 `processed/` + DynamoDB (30-day TTL) + pre-aggregated `curated/latest_summary.json` (written with S3 conditional writes + bounded retries — see `project-status-and-roadmap`, Error #6). Entities are filtered to meaningful Comprehend types (PERSON/LOCATION/ORGANIZATION/COMMERCIAL_ITEM/EVENT/TITLE); DATE/QUANTITY/OTHER noise is dropped from the `entities` field but kept in full in `entityDetails`.
5. **Analytics**: Glue Crawler → Athena SQL (console-only cold path) + static HTML/JS dashboard (Chart.js). The dashboard reads DynamoDB via the `timestamp-index` GSI (recent-events table, newest-first) and S3 `curated/latest_summary.json` (metric cards + entity chart); it does NOT query Athena.

## Tech Stack
- **IaC**: Terraform >= 1.11.0, S3 backend with native locking (`use_lockfile = true`)
- **Compute**: AWS Lambda (Python 3.11), Step Functions, EventBridge
- **Ingestion**: API Gateway (HTTP API), Kinesis Data Streams
- **Storage**: S3 (raw/processed/curated), DynamoDB (on-demand)
- **AI/ML**: Amazon Comprehend (sentiment + entity extraction)
- **Analytics**: Glue Crawler, Athena (console/ad-hoc cold path — not called by the dashboard), static dashboard (Vanilla JS + Chart.js v4.4.0 + AWS SDK v2)
- **Observability**: CloudWatch Dashboard (8 widgets), 6 alarms, SNS, SQS DLQs, X-Ray active tracing (both Lambdas, mode=Active)

## Dashboard data flow (dashboard/app.js)
- **Metric cards** (Total / Positive / Neutral / Negative / Mixed) ← `curated/latest_summary.json` (`total_records` + `sentiment_counts`), self-consistent aggregates.
- **Top Entities chart** ← same summary's `top_entities` (pre-aggregated by Merge Lambda, ~100ms read; avoids Athena latency/cost per page view).
- **Recent Events table** ← DynamoDB `query` on `timestamp-index` GSI (`recordType='text'`, `ScanIndexForward:false`, `Limit 50`) = true newest-first. (A plain `scan` returns hash-order, caps at the page size, and never surfaces new records — do not use scan here.) Five columns: Time / Sentiment / Confidence / **Text** / Entities. The Text column shows `textPreview` truncated by CSS with the full string in a `title` tooltip on hover; `escapeHtml()` on both the cell and the attribute. Renders at most 20 of the 50 returned rows.
- **Send Test Event button** ← `kinesis.putRecord` directly into the ingestion stream (same entry point as API Gateway), driving the full pipeline for a live demo.
- Runs entirely client-side (no backend); static IAM creds live in gitignored `config.js` (local demo only — prod would use Cognito Identity Pools or an API Gateway/Lambda proxy).

## Current Status (100% Complete ✅ — 2026-04-05)
- **Phases 0-8**: Complete (bootstrap through analytics/dashboard)
- **Phase 9**: All tasks complete (tests, load test, dashboard, alarms, security, cost review, architecture docs)
  - Runbooks and staging deployment intentionally skipped (not needed for portfolio)
- **Phase 10**: CI/CD — 6/6 tasks complete (OIDC role, CI workflow, deploy workflow, environment protection, testing, docs)
- **Post-completion maintenance (2026-08-18)**: dashboard + Merge Lambda entity-filter fixes — see `project-status-and-roadmap`.
- **Post-completion maintenance (2026-08-31)**: fixed a lost-update race in the curated summary (conditional writes) and a JSON assumption in `get_text_preview` that silently emptied previews for batch uploads; completed the Text-preview-on-hover column. 42 tests / 95% coverage. Committed as `0716b71`. See `project-status-and-roadmap` and `docs/errorlog.md` #6.

## Deployed Resources (dev, us-west-2)
- State bucket: `tf-state-aidp` (us-west-1)
- Data lake: `ai-dp-data-lake-dev-us-west-2`
- Kinesis: `ai-dp-dev-ingestion-stream` (KMS, PROVISIONED 1-shard; capacity mode parameterized via `kinesis_stream_mode`, default PROVISIONED)
- API Gateway: `https://pvqb2gzg7i.execute-api.us-west-2.amazonaws.com/ingest`
- Step Functions: `ai-dp-dev-orchestrator`
- DynamoDB: `ai-dp-dev-enriched-data` (GSI `timestamp-index`: `recordType` HASH + `timestamp` RANGE, projection ALL — powers newest-first dashboard queries; base key is `recordId` + `timestamp`; TTL on `expiresAt`, 30 days)
- Glue DB: `ai-dp-dev-analytics` | Athena: `ai-dp-dev-workgroup`
- CloudWatch Dashboard: `ai-dp-dev-operations`
- AWS Budget: `ai-dp-dev-monthly-budget` ($50/month, actual ~$12/month)
