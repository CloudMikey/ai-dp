# Interview Walkthrough — AI-Powered Serverless Data Pipeline

Five questions an interviewer is likely to ask, and the answers grounded in what was actually built.

---

## Q1: Walk me through the data flow from an API call to a DynamoDB record.

A client sends a `POST /ingest` request with a JSON payload to API Gateway. API Gateway is configured with a direct AWS service integration — no Lambda proxy — so it calls `kinesis:PutRecord` directly and returns a `SequenceNumber` to the caller. This keeps the ingest path fast and cheap.

The ETL Lambda polls the Kinesis stream in batches of up to 100 records. For each record it: decodes the base64 payload, validates required fields (`event_type`, `event_timestamp`), normalizes timestamps to UTC, and writes to S3 at `raw/year=YYYY/month=MM/day=DD/{sequenceNumber}.json`. Using the Kinesis sequence number as the filename is deliberate — if the Lambda retries a failed record, it writes to the same S3 key, preventing duplicate files. A UUID would create a new file on every retry.

The S3 write fires an EventBridge rule filtered to the `raw/` prefix. EventBridge starts a Step Functions execution, passing the bucket name and key as input. Step Functions reads the raw file, runs `DetectSentiment` and `DetectEntities` in parallel (halving enrichment time vs. sequential), then invokes the Merge Lambda with both results.

The Merge Lambda writes three things: the full enriched record to `processed/`, a running aggregate summary to `curated/latest_summary.json`, and a DynamoDB item with a 30-day TTL. The DynamoDB write uses the record ID as the partition key and timestamp as the sort key, enabling range queries by time.

End-to-end latency from API call to DynamoDB: approximately 3–8 seconds depending on Kinesis batch polling interval.

---

## Q2: Why Kinesis instead of SQS for streaming ingestion?

Three reasons:

**Replay.** Kinesis retains records for up to 7 days. If the ETL Lambda has a bug that corrupts data, you can fix the Lambda and replay the stream from an earlier position. SQS deletes messages on successful consumption — no replay.

**Ordering.** Kinesis guarantees ordering within a shard. For event streams where sequence matters (clickstreams, audit logs), this is important. SQS standard queues are unordered.

**Throughput model.** Kinesis is pull-based with configurable batch sizes (up to 10,000 records per batch). For a pipeline where downstream processing is the bottleneck, this is easier to reason about than SQS's push model.

The tradeoff: Kinesis requires shard management and costs more at low throughput than SQS. For this project's dev workload, that's acceptable. At high volume, Kinesis Enhanced Fan-Out would be the next scaling step.

---

## Q3: You used AI tools to build this — what did the AI generate vs. what did you add?

Claude Code was used for infrastructure scaffolding, test generation, and documentation structure. The Terraform module skeletons, initial IAM policies, and Lambda boilerplate were AI-generated starting points.

Three specific places where I caught problems and fixed them:

**DecimalEncoder.** The AI-generated Merge Lambda used `json.dumps()` to serialize enriched records before writing to S3. Athena was returning `HIVE_CURSOR_ERROR` on queries against the processed layer. The root cause: Python floats like `0.9999` were serializing as `9.999e-01` (scientific notation), which Athena's Hive-based reader rejected. I diagnosed this by inspecting the raw S3 files, traced it to float serialization, and built a custom `DecimalEncoder` class that normalizes all floats to standard decimal notation before the S3 write. The AI-generated fix attempt (using `Decimal` from the standard library) still produced scientific notation in edge cases — the final implementation required understanding exactly how Python's JSON encoder handles numeric types.

**IAM over-permissiveness.** Initial policies were broad (bucket-level `s3:*`). During a dedicated security audit I reviewed all 7 IAM roles, identified unnecessary permissions, and scoped each to the minimum required action and resource. For example, the ETL Lambda's S3 policy was narrowed to `s3:PutObject` on `{bucket_arn}/raw/*` only, and `s3:PutObjectAcl` was removed entirely — it had been included "just in case" but is unnecessary when using bucket policies for access control.

**Comprehend region pivot.** The AI scaffolding placed all resources in `us-west-1`. Comprehend is not available in `us-west-1`. I hit this during integration testing, diagnosed the cause (not a permissions issue — a service availability issue), evaluated three options (cross-region calls, mock Lambda, full migration), and migrated all application resources to `us-west-2` while keeping the Terraform state bucket in `us-west-1`. The options analysis is documented in `docs/errorlog.md`.

---

## Q4: Your CI pipeline has a lot of re-trigger commits. What was happening?

The OIDC-based GitHub Actions workflow requires an IAM role with exact permissions. Those permissions aren't fully known until you run the workflow and observe what it tries to do. There were three main iteration cycles:

1. **Initial OIDC trust policy** — The role's trust policy needed the exact GitHub repo and branch conditions in the `sub` claim. Getting the condition syntax right (`repo:owner/repo:ref:refs/heads/*`) required a few iterations.

2. **Terraform plan permissions** — `terraform plan` needs to read every resource type it manages. Missing `sts:GetCallerIdentity`, `s3:ListBucket` on the state bucket, and several `ec2:Describe*` actions that Terraform calls even for non-EC2 resources caused failures that were only visible at runtime.

3. **tflint plugin installation** — The tflint action was deprecated. I replaced it with a binary install step (`curl` from GitHub releases), which also required pinning a specific version to avoid rate-limiting on the GitHub API during CI runs.

The iteration is visible in the PR #1 commit history. The workflow now runs clean: fmt check, validate, tflint, tfsec at MEDIUM+ severity, and `terraform plan` with output posted as a PR comment.

---

## Q5: What would you change if this needed to handle 100x the current load?

The current setup has one Kinesis shard (~1,000 records/sec write capacity) and on-demand DynamoDB. At 100x load, the first constraints would be:

**Kinesis sharding.** One shard is fine for dev. At scale, I'd increase shard count based on throughput requirements and consider Enhanced Fan-Out consumers to avoid shared 2MB/s read throughput across consumers.

**Step Functions concurrency.** One S3 object created = one Step Functions execution. At high batch upload volume, this could hit the default concurrency limit (1,000 concurrent executions). I'd add a fan-out pattern: S3 event → SQS → Lambda fan-out → Step Functions, with SQS acting as a buffer.

**DynamoDB write capacity.** On-demand billing works fine for unpredictable dev traffic but gets expensive at sustained high throughput. At scale I'd switch to provisioned capacity with auto-scaling, and evaluate whether 30-day TTL cleanup is keeping table size manageable.

**Athena query costs.** Athena charges per TB scanned. At scale, adding Glue partition indexes and converting processed data to Parquet (columnar) would reduce scan costs significantly. The Glue Crawler already catalogs partitions — the schema change is the main work.

**CI/CD promotion gates.** Currently there's no staging environment — changes go from PR → main → dev. At production scale I'd add a staging account with a separate Terraform workspace and require integration tests to pass before promoting to prod.
