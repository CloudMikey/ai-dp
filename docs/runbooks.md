# Runbooks

Step-by-step procedures for operating the dev pipeline. All resources are in `us-west-2` (the Terraform state bucket is the only thing in `us-west-1`).

| # | Runbook | Use when |
|---|---------|----------|
| 1 | [Deploy](#1-deploy) | Shipping a change |
| 2 | [Roll back a bad deploy](#2-roll-back-a-bad-deploy) | A deploy broke the pipeline |
| 3 | [Alarm response](#3-alarm-response) | An SNS alarm email arrives |
| 4 | [Replay: streaming path (ETL DLQ)](#4-replay-streaming-path-etl-dlq) | `etl-dlq-depth` fired |
| 5 | [Replay: batch path (failed Step Functions)](#5-replay-batch-path-failed-step-functions) | `step-functions-failures` fired |
| 6 | [Repair the curated summary](#6-repair-the-curated-summary) | Dashboard total doesn't match DynamoDB |
| 7 | [Reset data for a clean retest](#7-reset-data-for-a-clean-retest) | Starting a test run from zero |
| 8 | [Kinesis load-test mode toggle](#8-kinesis-load-test-mode-toggle) | Running a burst load test |

> **Read this before any replay.** Replays are **not idempotent**. The Merge Lambda generates `recordId` with `uuid4` and writes a new `processed/` object every time, so replaying a record that already succeeded creates a duplicate DynamoDB row and double-counts the summary. Always confirm a record is actually missing before replaying it (each section below shows how), and run [Runbook 6](#6-repair-the-curated-summary) afterward.

---

## 1. Deploy

Deploys run through GitHub Actions. Full workflow detail is in [cicd.md](cicd.md).

1. Branch from `main`, make the change, and run locally:
   ```powershell
   terraform fmt -check -recursive        # from the repo root, same as CI
   terraform -chdir=envs/dev validate
   python -m pytest lambdas/ -v
   ```
2. Open a PR. `ci.yml` runs fmt/validate/tflint/tfsec/plan and posts the plan as a PR comment.
3. **Read the plan comment.** Stop if it shows unexpected `destroy` or `replace` actions, especially on the S3 bucket, DynamoDB table, or Kinesis stream (data loss).
4. Merge. `deploy.yml` applies the saved plan to `dev`.
5. Verify with a smoke test:
   ```powershell
   $api = terraform -chdir=envs/dev output -raw api_gateway_invoke_url   # already ends in /ingest
   curl -X POST $api `
     -H "Content-Type: application/json" -H "X-Partition-Key: smoke" `
     -d '{"event_type":"smoke","event_timestamp":"2026-01-25T12:00:00Z","text":"Smoke test: fast shipping, great product."}'
   ```
   Within ~1 minute a new row should appear in the dashboard and the `ai-dp-dev-operations` CloudWatch dashboard should show an ETL invocation with no errors.

**If apply fails midway:** state may be partially applied. Run `terraform -chdir=envs/dev plan` locally to see what is left, then fix forward in a new PR. If it fails with `Error acquiring state lock`, another run is still going; wait for it.

---

## 2. Roll back a bad deploy

Terraform has no "undo". You roll back by deploying the previous code.

1. Find the merge commit that caused the problem: `git log --oneline main -10`.
2. Revert it on a branch and open a PR:
   ```powershell
   git checkout main; git pull
   git checkout -b revert/<short-name>
   git revert -m 1 <merge-commit-sha>
   git push -u origin revert/<short-name>
   ```
3. Check the CI plan: it should be the exact inverse of the bad change. Merge it. `deploy.yml` applies it.
4. Lambda code rolls back too. Both Lambdas are packaged by `archive_file` from `lambdas/`, so reverting the Python files changes `source_code_hash` and Terraform redeploys the old code.
5. Re-run the smoke test from Runbook 1, then replay anything that failed during the outage (Runbooks 4 and 5).

**Caution:** reverting a change that *created* a stateful resource (bucket, table, stream) will destroy it and its data. Check the plan for `destroy` first.

---

## 3. Alarm response

All 6 alarms publish to SNS topic `ai-dp-dev-cloudwatch-alarms`, which emails the alarm address. First, see what is firing right now:

```powershell
aws cloudwatch describe-alarms --state-value ALARM --region us-west-2 --query "MetricAlarms[].[AlarmName,StateReason]" --output table
```

| Alarm | Fires when | Severity | Go to |
|-------|-----------|----------|-------|
| `ai-dp-dev-etl-dlq-depth` | ETL DLQ has > 0 messages (1 min) | Critical | [3a](#3a-etl-dlq-depth) |
| `ai-dp-dev-etl-lambda-error-rate` | ETL errors > 5% of invocations, 2 × 5 min | High | [3b](#3b-lambda-error-rate-etl-or-merge) |
| `ai-dp-dev-merge-lambda-error-rate` | Merge errors > 5% of invocations, 2 × 5 min | High | [3b](#3b-lambda-error-rate-etl-or-merge) |
| `ai-dp-dev-kinesis-iterator-age` | Oldest unread record > 60 s, 2 × 5 min | Medium | [3c](#3c-kinesis-iterator-age) |
| `ai-dp-dev-step-functions-failures` | > 3 failed executions in 5 min | High | [3d](#3d-step-functions-failures) |
| `ai-dp-dev-merge-dlq-depth` | Merge DLQ has > 0 messages (1 min) | Critical | [3e](#3e-merge-dlq-depth) |

Once you've fixed it, the alarm returns to `OK` by itself when the metric recovers (`treat_missing_data = notBreaching`). DLQ alarms stay red until the queue is empty.

### 3a. ETL DLQ depth

A Kinesis batch failed 3 retries and was discarded. **Time-sensitive:** the DLQ message is only a pointer into the stream, and the stream keeps data for **24 hours**. After that the records are gone for good, even though the DLQ keeps the pointer for 14 days.

1. Find the cause in the ETL logs:
   ```powershell
   aws logs tail /aws/lambda/ai-dp-dev-etl --since 1h --filter-pattern "ERROR" --region us-west-2
   ```
   Common causes are `Missing required field: event_type` / `event_timestamp` (a bad payload) or an S3 `ClientError` (permissions or throttling).
2. If it's a code or IAM bug, fix and deploy (Runbook 1) first, then replay.
3. Replay the batch: [Runbook 4](#4-replay-streaming-path-etl-dlq).

### 3b. Lambda error rate (ETL or Merge)

1. Tail the function's errors (`ai-dp-dev-etl` or `ai-dp-dev-merge`):
   ```powershell
   aws logs tail /aws/lambda/ai-dp-dev-merge --since 1h --filter-pattern "ERROR" --region us-west-2
   ```
2. Find out whether it lines up with a deploy (`git log`, Actions tab). If so, use [Runbook 2](#2-roll-back-a-bad-deploy).
3. If not, look for throttling or an AWS-side issue: `Throttles` on the CloudWatch dashboard, `ProvisionedThroughputExceeded` from DynamoDB, or S3 `SlowDown`.
4. Once errors stop, the alarm clears after two clean 5-minute periods. Records lost in the meantime show up as an ETL DLQ alarm (streaming) or Step Functions failures (batch). Follow those runbooks.

### 3c. Kinesis iterator age

The ETL Lambda is falling behind the stream (consumer lag). If lag approaches the 24-hour retention, **data is lost**.

1. Check whether ETL is failing rather than slow. A batch that keeps failing blocks its shard while it retries 3 times. If the ETL error rate is also high, go to [3b](#3b-lambda-error-rate-etl-or-merge).
2. Check whether the stream is getting more data than usual: look at `IncomingRecords` on the dashboard. A 1-shard PROVISIONED stream handles 1 MB/s or 1,000 records/s of writes.
3. For a sustained burst, temporarily switch to ON_DEMAND ([Runbook 8](#8-kinesis-load-test-mode-toggle)).
4. The alarm clears when the consumer catches up. Nothing needs replaying unless the ETL DLQ also fired.

### 3d. Step Functions failures

More than 3 batch executions failed within 5 minutes.

1. List recent failures:
   ```powershell
   $sm = aws stepfunctions list-state-machines --region us-west-2 --query "stateMachines[?name=='ai-dp-dev-orchestrator'].stateMachineArn" --output text
   aws stepfunctions list-executions --state-machine-arn $sm --status-filter FAILED --max-results 20 --region us-west-2 --query "executions[].[name,startDate]" --output table
   ```
2. Inspect one:
   ```powershell
   aws stepfunctions describe-execution --execution-arn <arn> --region us-west-2 --query "[error,cause]"
   ```
3. Match the error to a cause:

   | Error | Cause | Fix |
   |-------|-------|-----|
   | `Comprehend.TextSizeLimitExceededException` | File is over 5,000 bytes (`DetectSentiment` limit) | Split or trim the file and re-upload. **Not a pipeline bug, so don't replay as-is.** |
   | `S3.NoSuchKeyException` | Object deleted before the execution read it | Usually ignore |
   | `MergeLambdaError` | Merge Lambda failed after retries | Check `/aws/lambda/ai-dp-dev-merge` logs, fix, then replay |
   | `Comprehend.ThrottlingException` | Too many concurrent uploads | Replay more slowly |

4. Replay the failed executions: [Runbook 5](#5-replay-batch-path-failed-step-functions).

### 3e. Merge DLQ depth

> **Known gap:** this alarm will almost certainly never fire. The Merge Lambda's `dead_letter_config` only captures **asynchronous** invocations, but Step Functions calls Merge **synchronously** and handles the failure itself (`Catch` → `MergeFailed`). Merge failures show up as **Step Functions failures (3d)** instead. The same applies to the ETL Lambda's own `dead_letter_config`. Its DLQ messages come from the Kinesis event source mapping's `on_failure` destination, not from that setting.

If it does fire, something invoked Merge asynchronously (for example, a manual `aws lambda invoke --invocation-type Event`). Read the message (Runbook 4, step 1, with the merge queue) to see the original payload.

---

## 4. Replay: streaming path (ETL DLQ)

**Deadline: 24 hours from the original ingestion** (the Kinesis retention period).

You can't push the DLQ message back to Kinesis as-is. `aws sqs start-message-move-task` doesn't apply either, because it only redrives DLQs whose source is another SQS queue. The message contains **only the batch's location in the stream**, so you re-read the records from Kinesis and put them back.

1. **Read the DLQ message** (without deleting it):
   ```powershell
   $q = aws sqs get-queue-url --queue-name ai-dp-dev-etl-dlq --region us-west-2 --query QueueUrl --output text
   aws sqs receive-message --queue-url $q --max-number-of-messages 1 --visibility-timeout 300 --region us-west-2
   ```
   In the `Body`, note `KinesisBatchInfo.shardId`, `startSequenceNumber`, `endSequenceNumber`, and `batchSize`. Keep the `ReceiptHandle` for step 6.

2. **Fetch the records** from the start of the failed batch:
   ```powershell
   $it = aws kinesis get-shard-iterator --stream-name ai-dp-dev-ingestion-stream --shard-id <shardId> `
     --shard-iterator-type AT_SEQUENCE_NUMBER --starting-sequence-number <startSequenceNumber> `
     --region us-west-2 --query ShardIterator --output text
   aws kinesis get-records --shard-iterator $it --limit <batchSize> --region us-west-2 > failed-batch.json
   ```
   If this errors or returns no records, the 24-hour window has passed and the data is gone. Delete the DLQ message (step 6) and note the loss in `docs/errorlog.md`.

3. **Skip records that already succeeded.** ETL processes a batch in order and stops at the first bad record, so the ones before it are already in S3 at `raw/year=YYYY/month=MM/day=DD/<SequenceNumber>.json`. For each record in `failed-batch.json`, check:
   ```powershell
   aws s3 ls s3://ai-dp-data-lake-dev-us-west-2/raw/ --recursive --region us-west-2 | Select-String "<SequenceNumber>"
   ```
   A match means it already succeeded, so skip it.

4. **Decode and check each remaining record.** `Data` is base64:
   ```powershell
   [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("<Data>"))
   ```
   If the payload itself is invalid (missing `event_type`, or missing both `event_timestamp` and `timestamp`), it will fail again. Fix the payload by hand or drop it. Replaying only makes sense after a code, IAM, or transient fix.

5. **Re-send each record** through the API (the same path real clients use):
   ```powershell
   curl -X POST $api `
     -H "Content-Type: application/json" -H "X-Partition-Key: replay" -d '<decoded JSON>'
   ```
   (`$api` is from Runbook 1, step 5.) It gets a new sequence number and flows through ETL → `raw/` → Step Functions as normal.

6. **Delete the DLQ message** once every record is replayed or deliberately dropped:
   ```powershell
   aws sqs delete-message --queue-url $q --receipt-handle "<ReceiptHandle>" --region us-west-2
   ```
7. Run [Runbook 6](#6-repair-the-curated-summary) to make sure the summary is consistent.

---

## 5. Replay: batch path (failed Step Functions)

The original file stays readable in `raw/` for 90 days, so within that window a batch failure can be replayed by starting a new execution with the original input. After 90 days the lifecycle rule moves it to Glacier (it must be restored before Step Functions can read it), and at 180 days it is deleted. Failed executions can be inspected for 90 days.

1. **Check the record is really missing.** `MergeFailed` can happen *after* the DynamoDB write, since Merge writes `processed/` → DynamoDB → summary in that order. Look for the source file in the table:
   ```powershell
   aws dynamodb scan --table-name ai-dp-dev-enriched-data --region us-west-2 `
     --filter-expression "contains(rawDataLocation, :k)" `
     --expression-attribute-values '{\":k\":{\"S\":\"<raw object key>\"}}' --query "Count"
   ```
   If `Count` is greater than 0, don't replay. Just run Runbook 6.

2. **Replay with the original input:**
   ```powershell
   $in = aws stepfunctions describe-execution --execution-arn <failed-arn> --region us-west-2 --query input --output text
   $in | Out-File -Encoding ascii replay-input.json
   aws stepfunctions start-execution --state-machine-arn $sm --input file://replay-input.json --region us-west-2
   ```
   (`$sm` is from Runbook 3d, step 1.) For many failures, loop over the `list-executions` output, and pause between starts if the cause was throttling.

   *Alternative:* copy the object over itself to fire a fresh S3 `Object Created` event:
   `aws s3 cp s3://ai-dp-data-lake-dev-us-west-2/<key> s3://ai-dp-data-lake-dev-us-west-2/<key> --metadata-directive REPLACE --region us-west-2`

3. Confirm the new execution status is `SUCCEEDED`:
   ```powershell
   aws stepfunctions list-executions --state-machine-arn $sm --max-results 5 --region us-west-2 --query "executions[].[name,status]" --output table
   ```
4. Run [Runbook 6](#6-repair-the-curated-summary).

---

## 6. Repair the curated summary

The dashboard's totals come from one S3 object (`curated/latest_summary.json`). Concurrent writes, partial failures, or replays can make it drift from DynamoDB, which is the source of truth. Background: `docs/errorlog.md` Error #6.

```powershell
python scripts/rebuild_summary.py --dry-run   # shows current vs recomputed totals
python scripts/rebuild_summary.py             # writes the recomputed summary
```

The rewrite is an absolute overwrite, not an increment, so it's safe to run any number of times.

---

## 7. Reset data for a clean retest

Use the `/reset-data` slash command ([.claude/commands/reset-data.md](../.claude/commands/reset-data.md)). It backs up first, then clears **only** the curated summary and the DynamoDB items. It never touches `raw/` or `processed/`, so the history stays replayable.

---

## 8. Kinesis load-test mode toggle

The default is `PROVISIONED`, 1 shard (≈ $11/mo). `ON_DEMAND` costs a flat ≈ $29/mo regardless of traffic, so it's only for burst tests.

1. In [envs/dev/main.tf](../envs/dev/main.tf), set `kinesis_stream_mode = "ON_DEMAND"`. Open a PR, check the plan (it should be an in-place update, **not** replace), and merge.
2. Run the test: `python scripts/load_test.py`.
3. **Revert the same day:** set `kinesis_stream_mode = "PROVISIONED"`, then PR and merge. AWS allows only two capacity-mode switches per stream per 24 hours, so plan both switches together.
4. Check the Budget (`ai-dp-dev-monthly-budget`) a few days later to confirm costs have dropped back.
