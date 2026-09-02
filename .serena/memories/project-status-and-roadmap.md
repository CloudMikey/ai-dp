# Project Status & Roadmap

## Current Status (100% Complete) — Updated 2026-06-28

**Branch/deploy note (2026-06-28):** All work merged to `main` via PR #2 (CI/CD, X-Ray, portfolio hardening, Kinesis cost fix). Deploy path is now push to `main` → `deploy.yml` runs `terraform apply`. Before this, `main` was ~39 commits stale and deploys were done locally via `terraform apply`.

## Post-completion maintenance (2026-08-18) — dashboard + entity-filter fixes

⚠️ **These changes were deployed via a LOCAL `terraform apply` but were UNCOMMITTED at time of writing — live infra is AHEAD of git.** Commit on `test/deploy-workflow` and PR to `main` to reconcile, otherwise a CI redeploy from `main` would overwrite the deployed Merge Lambda fix with the old code. (Verify current git state before assuming.)

- **Merge Lambda entity filtering (DEPLOYED to `ai-dp-dev-merge`):** `merge_handler.py` now filters `entity_texts` to a module-level `MEANINGFUL_ENTITY_TYPES` frozenset (PERSON/LOCATION/ORGANIZATION/COMMERCIAL_ITEM/EVENT/TITLE), dropping Comprehend DATE/QUANTITY/OTHER noise (e.g. `00:00`, bare numbers, timestamps). Full unfiltered entity set is preserved in `entityDetails` (processed/ layer) for the Athena cold path. Added `test_filters_noise_entity_types` — merge unit tests now 17, all passing.
- **Dashboard `app.js` (local, not deployed anywhere — static files):** recent-events table now `query`s the DynamoDB `timestamp-index` GSI (newest-first) instead of `scan` (scan returned hash-order, capped at 50 items, and never surfaced new records). Metric cards now read `total_records` + `sentiment_counts` from `curated/latest_summary.json` (self-consistent aggregates) instead of tallying a 50-item scan sample.
- **Dashboard Athena removal (local):** removed unused `ATHENA_*` and `DLQ_URL` keys from `dashboard/config.js`; rewrote `dashboard/README.md` to match the real implementation (DynamoDB + S3 curated summary + Kinesis test button). Athena is the CONSOLE-ONLY cold path — deliberately NOT wired into the dashboard.
- **Curated summary caveats:** `update_curated_summary` in the Merge Lambda is a running tally that (a) does read-modify-write with no locking → lost updates under concurrent merges, and (b) truncates `top_entities` to top-10 on every write and never decrements → can freeze on stale "ghost" entities from TTL-expired records. Reliable reset = deterministic rebuild from DynamoDB (or from `processed/` `entityDetails` with the type filter), then overwrite `curated/latest_summary.json`.
- **DynamoDB TTL = 30 days on `expiresAt`.** Records auto-expire; if the environment clock jumps forward, older records can be swept early (observed this session). The S3 data lake (raw/processed) has no TTL and is the permanent archive.
- **Dashboard summary fetch caching:** the browser can cache `s3.getObject` of `latest_summary.json`, so summary updates may need a hard reload (Ctrl+Shift+R). Optional fix on the table: add `ResponseCacheControl: 'no-cache'` to the getObject call (not yet applied).

### Completed Phases (0-8)
- **Phase 0**: Bootstrap (S3 state bucket `tf-state-aidp`)
- **Phase 1**: Data Lake (S3 three-tier: raw/processed/curated)
- **Phase 2**: Streaming Ingestion (API Gateway → Kinesis → ETL Lambda → S3)
- **Phase 3**: Batch Ingestion (S3 → EventBridge → Step Functions)
- **Phase 4**: Step Functions Orchestration
- **Phase 5**: DynamoDB Hot Store
- **Phase 6**: AI Enrichment (Amazon Comprehend - sentiment + entity extraction)
- **Phase 7**: Merge Lambda & Complete Pipeline
- **Phase 8**: Analytics & Dashboard (Glue, Athena, Chart.js dashboard)

### Phase 9: Production Hardening (7/8 tasks — 89%)
| Task | Status |
|------|--------|
| Lambda unit tests (33 tests, 96% coverage) | ✅ |
| Load testing (1000 events, 0% errors, P95=2044ms) | ✅ |
| CloudWatch Dashboard (8 widgets) | ✅ |
| CloudWatch Alarms (6 alarms + SNS) | ✅ |
| Security Review (IAM audit, KMS, tfsec) | ✅ |
| Cost Optimization ($12/month actual, $50 budget) | ✅ |
| Architecture Documentation | ✅ (2026-04-05) — `docs/architecture.md` |
| Operational Runbooks | REMOVED — not needed for portfolio |
| Staging Environment Deployment | SKIPPED — portfolio decision |

### Phase 10: CI/CD (6/6 tasks — 100%) ✅
| Task | Status |
|------|--------|
| AWS OIDC IAM Role Setup | ✅ (2026-03-22) |
| CI Workflow (`.github/workflows/ci.yml`) | ✅ (2026-04-05) |
| Deploy Workflow (`.github/workflows/deploy.yml`) | ✅ (2026-04-05) |
| Environment Protection Rules | ✅ (2026-04-05) |
| Workflow Testing | ✅ (2026-04-05) |
| CI/CD Documentation | ✅ (2026-04-05) — `docs/cicd.md` |

## Architecture Documentation (docs/architecture.md)
- High-level Mermaid flowchart (all services + data paths)
- Streaming path sequence diagram
- Batch path sequence diagram
- Step Functions state machine flowchart (7 states)
- Storage architecture (3-tier S3 + DynamoDB)
- Analytics layer diagram (3-source query strategy)
- API contract (endpoint, headers, request/response)
- Infrastructure summary tables

## Cost Summary
- **Budget**: $50/month
- **Actual**: ~$12/month when Kinesis is PROVISIONED (largest driver: Kinesis ~$11/mo, 1 shard)
- **Kinesis capacity-mode regression (fixed 2026-06-28)**: stream was flipped to ON_DEMAND during Phase 9 load testing (commit aa843b6, 2026-01-26) and left there. ON_DEMAND bills a flat ~$0.04/stream-hr (~$29/mo) regardless of throughput — ~$90 avoidable spend Feb–Jun on ~1 MB/month traffic. Reverted to PROVISIONED 1-shard, now parameterized via `kinesis_stream_mode`/`kinesis_shard_count` (default PROVISIONED). Toggle ON_DEMAND only for burst load tests, then revert.

## Key Achievements
- 33 Lambda unit tests, 96% coverage (merge suite now 17 after the entity-filter test)
- 1000-event load test, 0% errors
- KMS encryption on Kinesis stream
- Least-privilege IAM with separate `iam.tf` files
- SQS DLQs for all async Lambda invocations
- S3 lifecycle policies (180-day raw, 365-day processed)
- Full CI/CD pipeline: OIDC auth, CI validation, automated deploy on merge
- Full architecture documentation with Mermaid diagrams
- X-Ray active tracing on both Lambdas (per-invocation latency + downstream call segments); `enable_xray_tracing` toggle, least-privilege IAM; cleared both tfsec aws-lambda-enable-tracing findings
