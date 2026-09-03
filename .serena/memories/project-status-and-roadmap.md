# Project Status & Roadmap

## Current Status (100% Complete) — Updated 2026-08-31

**Branch/deploy note (2026-06-28):** All work merged to `main` via PR #2 (CI/CD, X-Ray, portfolio hardening, Kinesis cost fix). Deploy path is now push to `main` → `deploy.yml` runs `terraform apply`. Before this, `main` was ~39 commits stale and deploys were done locally via `terraform apply`.

## Post-completion maintenance (2026-08-31) — concurrency fix + text preview

All committed as `0716b71` on `test/deploy-workflow` (this also swept up the previously-uncommitted 2026-08-18 work below). Both Lambda changes are deployed via `terraform apply`.

### Error #6: lost-update race in the curated summary (FIXED)

Eight `.txt` files uploaded in one `aws s3 cp --recursive` fired 8 concurrent Step Functions executions. All 9 records landed correctly in DynamoDB and S3, but `curated/latest_summary.json` read **7** — two increments silently overwritten by an unguarded read-modify-write on one shared object.

**Why it never surfaced before:** the streaming path serializes naturally (1 Kinesis shard, `parallelization_factor = 1`, so the ETL Lambda never runs alongside itself). The batch path has no such constraint. Same code, safe on one path, unsafe on the other — and only one had been exercised. The race had been identified earlier and judged tolerable on the grounds that the execution rate stays low; adding a batch path invalidated that assumption.

**Fix:** conditional writes in `update_curated_summary` — `IfMatch` pinned to the ETag read, `IfNoneMatch='*'` on the create path (both matter: without the latter, two Lambdas both seeing "no file" both create one). Bounded at `SUMMARY_MAX_ATTEMPTS = 5` with jittered exponential backoff. Counting logic extracted to a pure `_apply_to_summary()` so re-running an attempt is safe. Returns `Optional[str]` — `None` on exhaustion, logged, never raised (summary is non-critical; the record is already durable).

**Verified:** re-ran the identical scenario → 17 records, summary 17, counts sum exactly. CloudWatch showed 5 real `PreconditionFailed` retries across 4 concurrent invocations (max depth 2 of 5), proving the mechanism engages rather than the collisions simply not recurring.

**Known limit (documented in errorlog):** rare, not impossible. At higher write rates use a DynamoDB atomic counter (`ADD` in an `UpdateExpression`) — rejected here because it needs IAM + `terraform apply` + a dashboard change + a backfill for no benefit at 8 writers. *Conditional write = detect and retry; atomic counter = cannot conflict.*

### `get_text_preview` JSON assumption (FIXED)

`json.loads` on the raw object had been assumed since Phase 9 (commit `aa843b6`, 2026-01-26). True for streaming (ETL writes JSON), false for batch (plain `.txt`). The exception fell into a broad `except Exception → return None`, so previews were silently empty for seven months. Now a narrow inner `except json.JSONDecodeError` falls back to `body.strip()`. Both paths now produce identical record shapes.

### Text preview feature completed

`td.text-preview` CSS (with `cursor: help`) had existed unused since a removed column — the `colspan="5"` on a 4-column table was the fossil. Added the `Text` column between Confidence and Entities, rendering `item.textPreview` with the full text in a `title` tooltip; `escapeHtml()` on both the cell and the attribute (sample data contains `O'Hare`, `I'm`). All four `colspan` values corrected to 5.

### New tooling

- **`scripts/rebuild_summary.py`** — recomputes the summary from DynamoDB. Absolute write, not incremental, so it is idempotent; `--dry-run` reports drift without writing. This is the "deterministic rebuild" previously noted as missing. Conditional writes prevent *new* drift; this repairs *existing* drift.
- **`/reset-data`** (`.claude/commands/reset-data.md`) — clears only `curated/latest_summary.json` + DynamoDB items. Encodes hard constraints: never touch `raw/`/`processed/`, never delete the table (only items), never `aws s3 rm --recursive` on the versioned data lake, back up first, confirm in prose.
- **`test-data/batch/*.txt`** — 8 samples (3 POSITIVE / 3 NEGATIVE / 2 MIXED), pre-verified 8/8 against Comprehend.
- **`docs/dashboard-explained.md`** — plain-language dashboard walkthrough.

### Batch path input contract (verified empirically)

- Step Functions passes the **entire file body** to Comprehend (`"text_content.$" = "$.s3_response.Body"`) — no JSON parsing, no field extraction. Use plain `.txt`.
- **5,000 byte limit** — `DetectSentiment` caps at 5,000 (tested: 4,999 OK / 5,001 `TextSizeLimitExceededException`); `DetectEntities` caps at 100,000. They run in a `Parallel` state, so sentiment binds. No size guard exists — `size` is extracted into the state but never checked by a `Choice`.
- EventBridge matches **any** key under `raw/`, no extension filter. Any subfolder works.
- **1 file = 1 record = 1 sentiment.** Multiple paragraphs in one file yield one blended result, not one per paragraph.
- `aws s3 cp --recursive` is 8 separate `PutObject` calls → 8 EventBridge events → 8 concurrent executions. S3 has no "batch upload" concept.

### Test suite

42 tests, 95% coverage (CI gate 90%). Merge suite 17 → 25: five for the conditional-write path (retry-then-succeed via `unittest.mock.patch` + `side_effect`, exhaustion returns `None`, `IfNoneMatch` on create, `IfMatch` on update, 8-merge counts-sum-to-total) and three for plain-text preview extraction. Confirmed moto enforces both preconditions, so these exercise real semantics.

⚠️ CLAUDE.md previously claimed 33 tests / 96% — corrected to 42 / 95%.

---

## Post-completion maintenance (2026-08-18) — dashboard + entity-filter fixes

✅ **RESOLVED 2026-08-31** — committed as `0716b71` on `test/deploy-workflow` along with the concurrency fix above. (Still unmerged to `main`; verify current git state before assuming.)

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
