---
description: Reset pipeline data for a clean retest - clears the dashboard's two data sources only, leaving the S3 archive and all infrastructure untouched
tags: [operations, testing, aws]
---

# Reset Pipeline Data for Retesting

**Your task:** Clear the two data sources the dashboard reads, so the user gets an empty
dashboard to retest against. Everything else stays exactly as it is.

## Why only two things

The dashboard reads from exactly two places:

| Widget | Source |
|--------|--------|
| Metric cards + entities chart | `s3://<data-lake>/curated/latest_summary.json` |
| Recent Events table | DynamoDB `ai-dp-dev-enriched-data` |

`raw/` and `processed/` are the **permanent archive** and feed the Athena cold path. They
are not part of a dashboard reset. Wiping them destroys thousands of records for no benefit.

## Resources (dev, us-west-2)

- Data lake bucket: `ai-dp-data-lake-dev-us-west-2`
- DynamoDB table: `ai-dp-dev-enriched-data` — key is `recordId` (HASH) + `timestamp` (RANGE)

## Steps

### 1. Back up first

Save both to the scratchpad before deleting anything:

- `aws s3 cp s3://ai-dp-data-lake-dev-us-west-2/curated/latest_summary.json <scratchpad>/backup_latest_summary.json --region us-west-2`
- A full `aws dynamodb scan` of the table, written to `<scratchpad>/backup_dynamodb_items.json`

Also confirm and report the recoverability options: S3 bucket versioning status and
DynamoDB point-in-time recovery status. Both were ENABLED as of 2026-08-29.

### 2. Delete the curated summary

```
aws s3 rm s3://ai-dp-data-lake-dev-us-west-2/curated/latest_summary.json --region us-west-2
```

**Delete it — do not overwrite it with zeros.** The Merge Lambda only sets `first_record_at`
in its `NoSuchKey` branch (`lambdas/merge/merge_handler.py`), so an overwrite leaves a stale
date behind. Deleting lets the Lambda rebuild the file correctly on the next record.

### 3. Delete the DynamoDB items

Scan for keys and `delete_item` each one. Delete the **items**, never the table — dropping
the table would break Terraform state and force a re-apply.

### 4. Verify

Report a cleared-vs-preserved table:

```
CLEARED     DynamoDB items          -> 0
            curated/ live objects   -> 0

PRESERVED   raw/ files              (unchanged)
            processed/ files        (unchanged)
            infrastructure          (no Terraform drift)
```

The `raw/` and `processed/` counts **must** match what they were before. If either changed,
something went wrong — say so plainly.

## What the user should expect afterward

The dashboard will show `-` on the cards, "Curated summary not available" on the chart, and
"No recent events found" in the table. **This is correct, not broken.** The first test event
repopulates everything, with the summary counting from 1.

## Constraints

- Never touch `raw/` or `processed/`
- Never delete or modify the DynamoDB table itself, only its items
- Never run `aws s3 rm --recursive` on this bucket — versioning is enabled, so it adds
  delete markers rather than freeing anything, and the blast radius is far larger than needed
- Confirm with the user in prose before deleting; do not use a question dialog
