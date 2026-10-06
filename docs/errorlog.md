# Error Log

This file tracks all errors encountered during the AI-DP project development, along with attempted solutions and working fixes.

---

## Error #1: AWS Tag Conflicts with Provider default_tags

**Date**: Phase 2 - Data Lake Module Development
**Context**: Deploying S3 bucket resources with Terraform AWS Provider v3.38.0+

### Error Message
```
Error: error creating S3 bucket: InvalidTag: The TagValue you have provided is invalid
```

### Root Cause
AWS Provider's `default_tags` feature (introduced in v3.38.0) automatically applies tags to ALL resources. When modules manually added the same tags (Environment, Project, etc.), it created duplicate tags or tag conflicts.

### Attempted Solutions
1. L Tried merging tags in module locals:
   ```hcl
   locals {
     common_tags = merge(
       var.tags,
       {
         Environment = var.environment
         Project     = var.project_name
       }
     )
   }
   ```
   **Result**: Still caused conflicts with provider default_tags

2. L Tried conditionally applying tags based on environment
   **Result**: Inconsistent tagging and still had duplicates

### Working Fix 
**Solution**: Centralize all common tags in provider `default_tags` block, and only add resource-specific tags in modules.

```hcl
# Provider level (envs/*/main.tf)
provider "aws" {
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "AI-DP"
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      CostCenter  = "Engineering"
    }
  }
}

# Module level (modules/*/main.tf)
resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name

  # Only resource-specific tags, NO duplicates with provider tags
  tags = {
    Name        = local.bucket_name
    Description = "Data Lake for AI-enriched data"
    DataLayer   = "multi-tier"
  }
}
```

**Key Principle**: Provider `default_tags` handles global tags. Modules add only resource-specific tags.

---

## Error #2: S3 Lifecycle Rules with Empty Configuration

**Date**: Phase 2 - Data Lake Module Development
**Context**: Creating S3 lifecycle rules for the curated layer with all transitions disabled

### Error Message
```
Error: error creating S3 bucket lifecycle configuration: InvalidRequest: At least one action needs to be specified in a rule
```

### Root Cause
Lifecycle rules were being created even when all lifecycle values were set to 0 (disabled). AWS rejects lifecycle rules that have no actions configured.

### Attempted Solutions
1. L Tried using `status = "Disabled"` with conditional:
   ```hcl
   rule {
     id     = "lifecycle-rule"
     status = var.expiration_days > 0 ? "Enabled" : "Disabled"
     # ...
   }
   ```
   **Result**: Still creates the rule block, just marks it disabled. AWS still validates it and rejects empty rules.

2. L Tried setting default expiration to a high value (e.g., 3650 days)
   **Result**: Not flexible, forces lifecycle rules where they're not wanted

### Working Fix 
**Solution**: Use dynamic blocks with conditional `for_each` to prevent rule creation entirely when not needed.

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.data_lake.id

  # Only create rule if at least one lifecycle action is configured
  dynamic "rule" {
    for_each = var.expiration_days > 0 || var.transition_to_ia_days > 0 || var.transition_to_glacier_days > 0 ? [1] : []

    content {
      id     = "lifecycle-rule"
      status = "Enabled"

      filter {
        prefix = var.layer_name
      }

      # Conditional transitions using nested dynamic blocks
      dynamic "transition" {
        for_each = var.transition_to_ia_days > 0 ? [1] : []
        content {
          days          = var.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "transition" {
        for_each = var.transition_to_glacier_days > 0 ? [1] : []
        content {
          days          = var.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }

      dynamic "expiration" {
        for_each = var.expiration_days > 0 ? [1] : []
        content {
          days = var.expiration_days
        }
      }
    }
  }
}
```

**Key Principle**: Wrap optional lifecycle rules in dynamic blocks with conditional `for_each` to prevent empty rule creation.

**Implementation Note**: The curated layer now correctly has NO lifecycle configuration resource, while raw and processed layers have properly configured lifecycle rules.

---

## Preventive Patterns / Lessons Applied

This section documents patterns used to **avoid** errors based on previous learnings, even when no error occurred.

### Pattern #1: Provider default_tags Applied (Phase 3 - EventBridge)

**Phase**: Phase 3 - Batch Ingestion EventBridge Rule
**Date**: 2025-01-24
**Context**: Creating EventBridge rule resource in `modules/ingestion_stream/`

**Pattern Used**: Applied Error #1 lesson - used provider `default_tags` only, no tag duplication in module

```hcl
# modules/ingestion_stream/main.tf
resource "aws_cloudwatch_event_rule" "s3_batch_ingestion" {
  name        = "${var.project_name}-${var.environment}-s3-batch-ingestion"
  description = "Trigger Step Functions when batch data uploaded to S3 raw/"

  # Only resource-specific tags, provider handles global tags
  tags = {
    Name = "${var.project_name}-${var.environment}-s3-batch-ingestion"
  }
}
```

**Result**: No tag conflicts, clean deployment
**Lesson Reference**: Error #1 - AWS Tag Conflicts

---

### Pattern #2: Provider default_tags Applied (Phase 4 - Step Functions)

**Phase**: Phase 4 - Step Functions State Machine
**Date**: 2025-01-24
**Context**: Creating Step Functions state machine, IAM roles, CloudWatch log group

**Pattern Used**: Consistently applied Error #1 lesson across all resources (state machine, IAM roles, log group)

```hcl
# modules/step_functions/main.tf
resource "aws_sfn_state_machine" "orchestrator" {
  name     = "${var.project_name}-${var.environment}-orchestrator"
  role_arn = aws_iam_role.step_functions_execution.arn

  # Only resource-specific tags
  tags = {
    Name        = "${var.project_name}-${var.environment}-orchestrator"
    Description = "Orchestrates AI enrichment pipeline"
  }
}

resource "aws_iam_role" "step_functions_execution" {
  name = "${var.project_name}-${var.environment}-sfn-execution-role"

  # Only resource-specific tags
  tags = {
    Name = "${var.project_name}-${var.environment}-sfn-execution-role"
  }
}
```

**Result**: All resources deployed without tag conflicts
**Lesson Reference**: Error #1 - AWS Tag Conflicts

---

### Pattern #3: Least-Privilege IAM Scoping (Phase 4 - Step Functions)

**Phase**: Phase 4 - Step Functions IAM Roles
**Date**: 2025-01-24
**Context**: Creating IAM roles for Step Functions execution and EventBridge invocation

**Pattern Used**: Scoped IAM permissions to exact resources needed, avoiding wildcards

```hcl
# EventBridge → Step Functions (only StartExecution on specific state machine)
resource "aws_iam_role" "eventbridge_sfn_role" {
  name = "${var.project_name}-${var.environment}-eventbridge-sfn-role"
  # ... assume role policy ...
}

resource "aws_iam_role_policy" "eventbridge_sfn_invoke" {
  name = "eventbridge-sfn-invoke"
  role = aws_iam_role.eventbridge_sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "states:StartExecution"
        Resource = aws_sfn_state_machine.orchestrator.arn  # Specific ARN, not "*"
      }
    ]
  })
}

# Step Functions → CloudWatch Logs (scoped to specific log group)
resource "aws_iam_role_policy" "step_functions_logging" {
  name = "step-functions-logging"
  role = aws_iam_role.step_functions_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"  # CloudWatch Logs requires "*" for log delivery
      }
    ]
  })
}
```

**Why This Matters**:
- EventBridge role can ONLY invoke this specific state machine (not any state machine in account)
- Prevents privilege escalation
- Follows AWS least-privilege best practice
- Makes it easier to debug permission issues (exact resource scoping)

**Result**: Clean IAM policies, no overly permissive roles
**Security Principle**: Always scope IAM permissions to specific resources when possible

---

## Error #3: AWS DynamoDB Invalid Tag Value Characters

**Date**: Phase 5 - DynamoDB Hot Store Module Development
**Context**: Creating DynamoDB table with resource-specific tags

### Error Message
```
Error: creating AWS DynamoDB Table (ai-dp-dev-enriched-data): operation error DynamoDB: CreateTable, https response error StatusCode: 400, RequestID: FJHEMK5M9LK3PH4SC7ES8VMH5JVV4KQNSO5AEMVJF66Q9ASUAAJG, api error ValidationException: The Tag Value provided is invalid, Value: Hot store for AI-enriched data (recent records only)
```

### Root Cause
AWS DynamoDB (and other AWS services) restrict tag values to specific allowed characters. Tag values can only contain:
- Letters (a-z, A-Z)
- Numbers (0-9)
- Spaces
- Special characters: `+ - = . _ : / @`

Parentheses `()` are NOT allowed in tag values.

### Attempted Solutions
1. ✅ **Working Solution**: Removed parentheses from tag value

### Working Fix ✅
**Solution**: Replace parentheses with hyphens or other allowed characters

```hcl
# ❌ WRONG: Contains parentheses
tags = {
  Description = "Hot store for AI-enriched data (recent records only)"
}

# ✅ CORRECT: Use hyphens instead
tags = {
  Description = "Hot store for AI-enriched data - recent records only"
}
```

**Key Principle**: AWS tag values must use only allowed characters: letters, numbers, spaces, and `+ - = . _ : / @`. Avoid parentheses, brackets, quotes, or other special characters.

**Service Scope**: This restriction applies to most AWS services (DynamoDB, S3, Lambda, etc.), not just DynamoDB. Always validate tag values against AWS character restrictions.

---

## Error #4: AWS Comprehend Not Available in us-west-1

**Date**: Phase 6 - AI Enrichment Module Development
**Context**: Testing Step Functions integration with AWS Comprehend for sentiment analysis

### Error Message
```
Comprehend.InvalidRequestException: UNSUPPORTED_OPERATION: This operation is not supported in this region (Service: Comprehend, Status Code: 400, Request ID: 94be587f-db96-42fa-900b-70d25ba79f9b)
```

### Root Cause
AWS Comprehend is not available in all regions. Specifically, it is NOT available in `us-west-1` (N. California). The project was initially developed in `us-west-1` for cost optimization, but Comprehend requires a different region.

**Comprehend Available Regions** (as of 2025):
- `us-east-1` (N. Virginia) ✅
- `us-east-2` (Ohio) ✅
- `us-west-2` (Oregon) ✅
- `eu-west-1` (Ireland) ✅
- `eu-central-1` (Frankfurt) ✅
- `ap-southeast-1` (Singapore) ✅
- `ap-southeast-2` (Sydney) ✅
- And others...

NOT AVAILABLE in:
- `us-west-1` (N. California) ❌

### Options Considered

**Option 1**: Switch entire project to `us-west-2` ✅ RECOMMENDED
- **Pros**: Supports all AWS services (Comprehend, Rekognition, SageMaker, etc.)
- **Pros**: Simple - just update region variable
- **Pros**: Best for portfolio project (demonstrates full AI service integration)
- **Cons**: Slightly higher data transfer costs (negligible for dev/portfolio)

**Option 2**: Use cross-region Comprehend calls from `us-west-1`
- **Pros**: Keep existing infrastructure in `us-west-1`
- **Cons**: Complex IAM permissions and VPC endpoint configuration
- **Cons**: Higher latency and data transfer costs
- **Cons**: Not a clean architecture for portfolio demonstration
- **Rejected**: Overly complex for portfolio project

**Option 3**: Mock Comprehend with Lambda function
- **Pros**: Works in any region
- **Cons**: Not real AWS AI service integration (defeats purpose of portfolio)
- **Cons**: Doesn't demonstrate actual Comprehend usage
- **Rejected**: Misses learning opportunity and portfolio value

### Working Fix ✅
**Solution**: Migrate entire project from `us-west-1` to `us-west-2`

**Migration Steps**:
1. Update region variable in `envs/dev/terraform.tfvars`:
   ```hcl
   aws_region = "us-west-2"
   ```

2. Update S3 backend bucket name (region-specific):
   ```hcl
   # bootstrap/main.tf or manual S3 bucket creation
   bucket = "tf-state-aidp-us-west-2"  # Instead of existing us-west-1 bucket
   ```

3. Run `terraform destroy` in us-west-1 (optional - to clean up old resources)

4. Run `terraform init -reconfigure` to reinitialize with new backend

5. Run `terraform apply` to deploy in us-west-2

**Alternative Quick Fix** (for testing Phase 6 only):
- Just update `aws_region = "us-west-2"` in variables
- Run `terraform destroy` to clean up us-west-1 resources
- Run `terraform apply` to redeploy in us-west-2
- Keep existing S3 backend in us-west-1 (state file can be in different region than resources)

**Key Principle**: Always verify AWS service regional availability BEFORE architecture design. Use [AWS Regional Services List](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/) to check service availability.

**Portfolio Recommendation**: Use `us-west-2` or `us-east-1` for projects requiring AI/ML services (Comprehend, Rekognition, SageMaker, Bedrock). These regions have the most comprehensive AWS service coverage.

---

## Template for New Errors

```markdown
## Error #X: [Brief Description]

**Date**: [Date or Phase]
**Context**: [What were you doing when the error occurred]

### Error Message
```
[Exact error message from terminal/logs]
```

### Root Cause
[Explanation of why the error occurred]

### Attempted Solutions
1. L [First attempt]
   **Result**: [What happened]

2. L [Second attempt]
   **Result**: [What happened]

### Working Fix 
**Solution**: [Description of the fix]

```[language]
[Code example of the working solution]
```

**Key Principle**: [Lesson learned - the rule to prevent this in the future]
```

---

### Pattern #4: Idempotent S3 Writes with Kinesis Sequence Numbers (Phase 2 Enhancement)

**Phase**: Phase 2 - Streaming Ingestion Path Enhancement
**Date**: 2026-01-11
**Context**: Improving ETL Lambda to prevent duplicate S3 files on retry

**Pattern Used**: Replaced UUID-based filenames with Kinesis sequence numbers for idempotent writes

**Implementation**:
```python
# lambdas/etl/etl_handler.py

def process_record(record: Dict[str, Any]) -> Dict[str, str]:
    """Decode Kinesis record → Validate → Normalize → Write to S3."""

    # Extract sequence number for idempotent S3 writes (prevents duplicates on retry)
    sequence_number = record['kinesis']['sequenceNumber']

    # ... validation and normalization ...

    s3_key = write_to_s3(normalized_data, timestamp, sequence_number)
    return {'s3_key': s3_key, 'status': 'success'}

def write_to_s3(data: Dict[str, Any], timestamp: datetime, sequence_number: str) -> str:
    """Write to S3 with date partitions.

    Uses Kinesis sequence number for idempotent writes - retries overwrite same file.
    """
    year = timestamp.strftime('%Y')
    month = timestamp.strftime('%m')
    day = timestamp.strftime('%d')

    # Use sequence number instead of UUID for idempotent writes
    s3_key = f"{RAW_PREFIX}year={year}/month={month}/day={day}/{sequence_number}.json"

    # ... write to S3 ...
```

**Before (UUID):**
- Filename: `raw/year=2025/month=01/day=11/abc123-def456-789.json`
- Retry behavior: Creates NEW file with different UUID → Duplicates in S3
- Problem: Same record processed twice = two S3 files

**After (Sequence Number):**
- Filename: `raw/year=2025/month=01/day=11/49670192848271239842602659163669398716174920392225325058.json`
- Retry behavior: Overwrites SAME file → No duplicates
- Benefit: Same record processed twice = one S3 file (idempotent)

**Why This Works**:
- Kinesis sequence numbers are unique per shard and guaranteed by AWS
- When Lambda retries a failed record, it sends the **same sequence number**
- Writing to the same S3 key overwrites the previous attempt instead of creating duplicates
- No additional infrastructure needed (no deduplication logic, no DynamoDB tracking)

**Key Principle**: For streaming data pipelines, use deterministic identifiers (sequence numbers, event IDs) as filenames to ensure idempotent writes. Avoid random identifiers (UUIDs) that create duplicates on retry.

**Result**: ETL Lambda now implements production-ready idempotent writes for streaming ingestion path

**Note**: Batch ingestion path (direct S3 uploads) bypasses ETL Lambda, so clients control filenames. Deduplication for batch uploads is the client's responsibility.

---

---

## Error #5: IAM Policy Over-Permissive (s3:PutObjectAcl)

**Date**: Phase 9 - Security Review
**Context**: Security audit of ETL Lambda IAM permissions during Phase 9 Task 5

### Issue Description
ETL Lambda role included `s3:PutObjectAcl` permission, which was unnecessary for the Lambda's operation (simple PutObject to raw/ prefix).

### Root Cause
Permission was copied from example code or added "just in case" without verifying necessity. Modern S3 best practice is to use bucket policies instead of object ACLs.

### Security Impact
- LOW severity (over-permissive, but scoped to raw/* prefix)
- Could allow Lambda to modify object ACLs if compromised
- Violates least-privilege principle

### Discovery Method
Identified during systematic IAM audit of all 7 roles in the project.

### Working Fix
**Solution**: Remove s3:PutObjectAcl from IAM policy.

```hcl
# Before (modules/ingestion_stream/iam.tf)
Action = [
  "s3:PutObject",
  "s3:PutObjectAcl"  # Unnecessary
]

# After
Action = [
  "s3:PutObject"  # Sufficient for ETL operation
  # Note: s3:PutObjectAcl removed during security review - not needed for Lambda writes
  # Modern S3 best practice: Use bucket policies instead of object ACLs
]
```

**Testing**: Verified Lambda function still works after permission removal by sending test events through API Gateway.

**Key Principle**: Only grant permissions that are actively used. If unsure, remove and test. Prefer bucket policies over object ACLs.

## Error #6: Lost Updates in Curated Summary Under Concurrent Merges

**Date**: 2026-08-31
**Context**: Batch path testing — uploaded 8 `.txt` files to S3 `raw/` in a single `aws s3 cp --recursive`, triggering 8 concurrent Step Functions executions.

### Symptom

The dashboard metric cards showed **7 total records** when **9** had actually been processed. Sentiment counts were also short:

| Source | Total | POSITIVE | NEGATIVE | NEUTRAL | MIXED |
|--------|-------|----------|----------|---------|-------|
| DynamoDB (truth) | 9 | 3 | 3 | 1 | 2 |
| `curated/latest_summary.json` (cards) | 7 | 2 | 2 | 1 | 2 |

All 9 records were correctly written to DynamoDB and S3 `processed/`. **No data was lost — only the running tally undercounted.**

### Root Cause

Classic **lost-update race condition**. `update_curated_summary()` in `lambdas/merge/merge_handler.py` does an unguarded read-modify-write against a single shared S3 object:

```python
response = s3_client.get_object(Bucket=..., Key='curated/latest_summary.json')
summary = json.loads(response['Body'].read())
summary['total_records'] += 1
s3_client.put_object(Bucket=..., Key='curated/latest_summary.json', Body=json.dumps(summary))
```

There is no lock, no ETag check, and no conditional write. With 8 Merge Lambdas running concurrently, two or more read the same value before any of them wrote back:

```
Lambda A:  GET (total=5) ---- +1 ---- PUT (total=6)
Lambda B:      GET (total=5) ---- +1 ---- PUT (total=6)
               ^                          ^
         reads the SAME 5           B overwrites A; one increment lost
```

Two collisions occurred, so two increments vanished (one POSITIVE, one NEGATIVE).

**Why DynamoDB was unaffected**: each Lambda writes its own row keyed by a unique `recordId`, so concurrent writers never collide. The summary is the only place all 8 write to one shared object.

**Why this did not surface earlier**: the streaming path processes records through a single-shard Kinesis stream with `parallelization_factor = 1`, so the ETL Lambda never runs concurrently with itself. Merges are effectively serialized. The batch path has no such constraint — S3 uploads fire fully parallel executions.

### Attempted Solutions

1. **Upload files one at a time with a sleep between them** — works, but only by removing the concurrency the architecture is designed to have. Masks the bug rather than fixing it.

### Working Fix

**Applied 2026-08-31.** Conditional writes on the summary object, in `update_curated_summary()`:

```python
try:
    response = s3_client.get_object(Bucket=..., Key=summary_key)
    summary = json.loads(response['Body'].read().decode('utf-8'))
    condition = {'IfMatch': response['ETag']}      # only overwrite what we read
except s3_client.exceptions.NoSuchKey:
    summary = _empty_summary(enriched_data['mergedAt'])
    condition = {'IfNoneMatch': '*'}               # only create if nobody beat us

summary = _apply_to_summary(summary, enriched_data)

try:
    s3_client.put_object(..., **condition)
except ClientError as e:
    if e.response['Error']['Code'] not in ('PreconditionFailed', 'ConditionalRequestConflict'):
        raise
    delay = (2 ** attempt) * 0.05 + random.uniform(0, 0.05)   # jitter avoids lockstep retries
    time.sleep(delay)
    continue
```

S3 rejects a write whose precondition no longer holds, so a losing writer re-reads current state and reapplies its own increment rather than clobbering the winner. Bounded at 5 attempts; exhaustion logs a warning and returns `None` (the record is already durable in S3 and DynamoDB).

The `IfNoneMatch='*'` branch matters as much as `IfMatch` — without it, two Lambdas that both see "no file" would both create one and lose an increment. Reachable in practice after a `/reset-data`.

**Verification**: re-ran the exact failing scenario — 8 files uploaded in one `aws s3 cp --recursive`.

| | Before fix | After fix |
|--------|-----------|-----------|
| DynamoDB records | 9 | 17 |
| Summary `total_records` | 7 | **17** |
| Sentiment counts sum to total | no | **yes** |

CloudWatch confirmed the mechanism actually engaged rather than the collisions simply not recurring: 5 `PreconditionFailed` retries across 4 concurrent invocations, one needing 2 attempts, all recovering well inside the 5-attempt bound.

**Drift repair**: `scripts/rebuild_summary.py` recomputes the summary from DynamoDB (absolute write, idempotent). Conditional writes prevent new drift but do not repair existing drift — this fixed the 7-to-9 gap and doubles as the deterministic reset tool.

**Tests**: `lambdas/merge/test_merge.py` — retry-then-succeed, retry exhaustion returns `None`, `IfNoneMatch` on create, `IfMatch` on update, and an 8-merge scenario asserting counts sum to the total. Merge suite 17 to 22. Moto enforces both preconditions, so these exercise real semantics rather than just argument passing.

### Known Limitation

This makes lost updates **rare, not impossible**. Retries are bounded, so sustained high contention could still exhaust them. At the observed concurrency (8 writers, max depth 2) there is wide headroom.

At materially higher write rates the retry rate itself would become the bottleneck, and the correct fix is a **DynamoDB atomic counter** — `ADD` in an `UpdateExpression` removes the read-modify-write entirely instead of retrying around it. Rejected here as the heavier option: it needs an IAM change, a `terraform apply`, a dashboard read-path change, and a backfill, for no benefit at current scale.

Trade-off in one line: **conditional write = detect and retry; atomic counter = cannot conflict.**

### Related Issue

Batch-path records have no `textPreview` attribute, so `latest_text_preview` in the summary comes back empty. `get_text_preview()` expects the raw object to be the ETL Lambda's JSON, but batch files are plain text. Harmless for the dashboard table (that column is not rendered), but it is a real behavioral gap between the two ingestion paths.

### Key Principle

**Read-modify-write on a shared object is not safe under concurrency.** Any counter written by more than one concurrent writer needs an atomic operation or a conditional write. Verify the record count against the authoritative store (DynamoDB), not the derived aggregate.

---

## Error #7: CI Deploy Role Missing Permissions That Only New Changes Needed

**Date**: 2026-10-05
**Context**: PR #6 (pipeline hardening), which changed the state machine definition and the API Gateway stage, run through CI as `ai-dp-dev-github-actions`. A local `terraform plan` with admin credentials had succeeded.

### Symptom

Two failures, one after the other:

1. **CI plan failed.** The PR comment said `Terraform planned the following actions, but then encountered a problem` and listed 3 changes instead of the expected 5, with no error message.
2. **Deploy apply failed partway.** After fixing (1) and merging, 7 of 8 changes applied; the API stage update failed:

```
Error: updating API Gateway v2 Stage ($default): BadRequestException: Insufficient permissions to enable logging.
User: ...assumed-role/ai-dp-dev-github-actions/... is not authorized to perform: logs:CreateLogDelivery
```

### Root Cause

The CI role's permission policy lives in the AWS Console, not Terraform, so nothing kept it in step with what the code started asking AWS to do.

1. **`states:ValidateStateMachineDefinition`**: the AWS provider validated the changed state machine definition during `plan`, and the role couldn't call that API. The plan stopped at the state machine, which is why it reported 3 of 5 changes. (A June commit also touched the definition's `Comment`; I haven't confirmed whether that change went through CI before the provider started validating, or was applied with admin credentials.)
2. **`logs:CreateLogDelivery` and related actions**: the stage has access logging enabled, and API Gateway re-checks that the *caller* can manage log delivery on a stage update. The stage was created with admin credentials, and git history shows no stage change between CI going live and this PR.

**Why the PR comment showed no error**: `ci.yml` posted only the plan's stdout. Terraform writes errors to stderr.

### Attempted Solutions

None needed. `aws iam simulate-principal-policy` against the role confirmed each missing action before changing anything.

### Working Fix

1. Added `states:ValidateStateMachineDefinition` and the 7 log-delivery actions, both on `Resource: "*"` (neither is tied to a specific resource ARN). Re-ran CI, merged, re-ran the failed deploy: only the stage change remained, and it applied.
2. Audited the rest of the policy the same way and added actions the repo's own runbooks would hit: `kinesis:UpdateStreamMode` (Runbook 8), retention changes, `iam:UpdateAssumeRolePolicy`, policy versions, `iam:ListInstanceProfilesForRole`, `dynamodb:UpdateTable`, untag actions. The policy simulator also never matched the existing `kinesis:UpdateShardCount` grant against the stream ARN, so shard-count changes from CI likely would have failed too; moved both capacity actions to `Resource: "*"`, which works either way.
3. Tightened IAM while there: role actions scoped to `role/ai-dp-*` (was `*`), `iam:PassRole` limited by `iam:PassedToService` to the 5 services the pipeline uses, and an explicit `Deny` stopping the role from editing its own policies, trust policy, or deleting itself.
4. `ci.yml` now includes the plan's stderr in the PR comment. Both the PR comment and `deploy.yml`'s job summary redact the alarm email (it appears in resource addresses) and 12-digit account IDs, because GitHub masks secrets in logs but not in text a workflow posts.

**Verification**: 24 simulated decisions on the draft policy and 10 on the live role matched expectations, including the denials; Access Analyzer reported 0 findings. Deploy re-run succeeded; stage throttling, state machine, and alarms confirmed via the AWS CLI.

### Key Principle

**A permission policy managed outside code drifts from the code that depends on it, and the gap only shows up at plan or apply time, under the role that's missing it.** A local plan with admin credentials proves nothing about CI. Test with the real role (`simulate-principal-policy`) before merging changes that touch new APIs, and make the failure message visible where people look.

---

**Last Updated**: 2026-10-05
**Total Errors Documented**: 7
**Total Preventive Patterns Documented**: 4
