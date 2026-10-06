# Step Functions Orchestration Module

## What It Does

Orchestrates the batch AI-enrichment pipeline. When a file lands in the data lake `raw/` layer, EventBridge triggers this state machine, which reads the object from S3, runs Amazon Comprehend **sentiment and entity detection in parallel**, then invokes the Merge Lambda to write enriched results to the S3 `processed/` layer and the DynamoDB hot store.

**Data Flow**: S3 `raw/` upload → EventBridge → Step Functions → (read S3 → parallel Comprehend → Merge Lambda) → S3 `processed/` + DynamoDB

## Why Step Functions?

**Architecture Decision Justification:**
- **Visual Workflow Management**: State machine provides a graphical representation of pipeline flow
- **Built-in Error Handling**: Retry policies and `Catch` blocks without custom orchestration code
- **Parallel Execution**: Sentiment analysis and entity detection run concurrently, reducing latency
- **Serverless Orchestration**: No infrastructure to manage, pay-per-execution pricing
- **Audit Trail**: CloudWatch Logs capture every state transition for debugging

**Cost Consideration**: At $0.025 per 1,000 state transitions and ~10 transitions per execution, even 10,000 monthly batch uploads cost roughly $2.50 — negligible for the orchestration value provided.

## Resources Created

- **Step Functions State Machine** — 8-state workflow defined in Amazon States Language (ASL)
- **IAM Execution Role** — scoped to S3 read (`raw/`), Comprehend, Merge Lambda invoke, and CloudWatch Logs
- **CloudWatch Log Group** — captures execution logs at the configured level for debugging
- **IAM Policies** — separate inline policies for logging, S3 read, and Lambda invoke; Comprehend permissions attached via a managed policy passed in from the `ai_enrichment` module

## State Machine Workflow

| # | State | Type | Purpose |
|---|-------|------|---------|
| 1 | `PrepareComprehendInput` | Pass | Extract bucket / key / size from the EventBridge event |
| 2 | `ReadS3Object` | Task (SDK: `s3:getObject`) | Read the object's text content from `raw/` |
| 3 | `CheckFileFormat` | Choice | `.json` keys (streaming events) → step 4; anything else → step 7 |
| 4 | `ParseJsonEvent` | Pass | `States.StringToJson` turns the body into an object |
| 5 | `CheckForText` | Choice | `text` field present → step 6; otherwise `NoTextToAnalyze` (Succeed, no Comprehend calls) |
| 6 | `ExtractEventText` | Pass | Keep only the `text` field, so metadata isn't scored |
| 7 | `PrepareTextContent` | Pass | Plain-text batch files: the whole body is the document |
| 8 | `ComprehendAnalysis` | **Parallel** | Branch A: `DetectSentiment` · Branch B: `DetectEntities` (both AWS SDK Comprehend tasks) |
| 9 | `FormatResults` | Pass | Structure the sentiment + entity results for downstream writes |
| 10 | `InvokeMergeLambda` | Task (Merge Lambda) | Merge results → S3 `processed/` + DynamoDB. Has `Retry` (3 attempts, backoff 2.0) and `Catch` |
| 11 | `MergeComplete` | Succeed | Terminal success state |
| 12 | `MergeFailed` | Fail | Terminal failure state (entered via `Catch` if the merge fails after retries) |

`ReadS3Object` and both Comprehend tasks share one retry policy: errors a retry can't fix (text too long, invalid request, missing key, archived object) fail immediately; any other task failure retries 3 times with backoff and full jitter.

> Comprehend is invoked through Step Functions' native AWS SDK integrations (`arn:aws:states:::aws-sdk:comprehend:*`), so no glue Lambda is needed for the AI calls.

## Usage Example

```hcl
module "step_functions" {
  source = "../../modules/step_functions"

  environment  = "dev"
  project_name = "ai-dp"
  aws_region   = "us-west-2"

  # Pipeline integration
  data_lake_bucket_arn  = module.data_lake.bucket_arn          # S3 read scope (raw/)
  comprehend_policy_arn = module.ai_enrichment.comprehend_policy_arn
  merge_lambda_arn      = module.orchestration.lambda_function_arn

  # Logging
  log_retention_days = 7     # 7 days for dev, increase for prod
  log_level          = "ALL" # ALL, ERROR, FATAL, or OFF

  tags = {}
}
```

## Outputs

```hcl
# For the EventBridge target in the ingestion_stream module
module.step_functions.state_machine_arn

# For CloudWatch Logs testing
module.step_functions.log_group_name

# For Terraform resource references
module.step_functions.state_machine_id
```

## Testing

### End-to-end (recommended)

The simplest realistic test is to upload a file to the `raw/` layer — EventBridge triggers the
state machine automatically:

```powershell
echo '{"text":"AWS Comprehend makes sentiment analysis easy in Seattle."}' > test.json
aws s3 cp test.json s3://ai-dp-data-lake-dev-us-west-2/raw/test.json
```

Then watch the execution in the Step Functions console (`ai-dp-dev-orchestrator`) or tail the logs:

```powershell
aws logs tail /aws/states/ai-dp-dev-orchestrator --follow
```

### Manual start-execution

To start an execution directly, provide an input shaped like the EventBridge S3 event the
first state expects:

```json
{
  "detail": {
    "bucket": { "name": "ai-dp-data-lake-dev-us-west-2" },
    "object": { "key": "raw/test.json", "size": 64 }
  }
}
```

```powershell
aws stepfunctions start-execution `
  --state-machine-arn <state-machine-arn> `
  --input file://event.json
```

## Key Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | - | Environment name (dev, stg, prod) — validated |
| `project_name` | string | - | Project name for resource naming |
| `aws_region` | string | - | AWS region for resources |
| `data_lake_bucket_arn` | string | - | Data lake bucket ARN; scopes S3 read to `raw/*` |
| `comprehend_policy_arn` | string | - | Managed policy ARN granting `DetectSentiment` + `DetectEntities` |
| `merge_lambda_arn` | string | - | Merge Lambda ARN to invoke after enrichment |
| `log_retention_days` | number | `7` | CloudWatch log retention (days) — validated against AWS valid values |
| `log_level` | string | `"ALL"` | Step Functions log level (ALL, ERROR, FATAL, OFF) |
| `tags` | map(string) | `{}` | Additional tags merged with resource-specific tags |

## Amazon States Language (ASL) Highlights

The workflow uses several core ASL constructs (full definition in `main.tf`):

- **`Choice`** states (`CheckFileFormat`, `CheckForText`) route streaming JSON events and plain-text
  batch files to the right text-extraction step.
- **`Pass`** states (`PrepareComprehendInput`, `ParseJsonEvent`, `ExtractEventText`, `PrepareTextContent`, `FormatResults`) reshape the
  data between steps using `Parameters` and JSONPath (`$.detail.bucket.name`, etc.) — no compute cost.
- **AWS SDK service integrations** (`arn:aws:states:::aws-sdk:s3:getObject`,
  `arn:aws:states:::aws-sdk:comprehend:detectSentiment`) call AWS services directly from the state
  machine without a Lambda.
- **`Parallel`** runs the sentiment and entity branches concurrently; their outputs are collected
  into an array at `$.comprehend_results`.
- **`Retry` / `Catch`** on the Merge Lambda task retry transient Lambda errors
  (`Lambda.ServiceException`, `Lambda.TooManyRequestsException`) up to 3 times with exponential
  backoff, then route any remaining failure to the `MergeFailed` state.

## Security

**IAM Role Trust Policy:**
- Allows `states.amazonaws.com` to assume the role

**IAM Permissions (least privilege):**
- **S3**: `s3:GetObject`, `s3:GetObjectVersion` scoped to `raw/*` only (read of the ingestion entry point)
- **Comprehend**: `DetectSentiment` + `DetectEntities` via the managed policy from the `ai_enrichment` module
- **Lambda**: `lambda:InvokeFunction` scoped to the specific Merge Lambda ARN
- **CloudWatch Logs**: log-delivery actions on `Resource = "*"` — a wildcard **required by AWS** for
  Step Functions logging setup (AWS does not support resource-level permissions here).
  Ref: https://docs.aws.amazon.com/step-functions/latest/dg/cw-logs.html

**Least Privilege Principle**: every permission maps to a specific state in the workflow — S3 read for
`ReadS3Object`, Comprehend for the parallel branches, Lambda invoke for `InvokeMergeLambda`.

## Resources

- [AWS Step Functions Documentation](https://docs.aws.amazon.com/step-functions/)
- [Amazon States Language Specification](https://states-language.net/spec.html)
- [Step Functions AWS SDK service integrations](https://docs.aws.amazon.com/step-functions/latest/dg/supported-services-awssdk.html)
- [Terraform aws_sfn_state_machine Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine)
