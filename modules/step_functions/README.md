# Step Functions Orchestration Module

## What It Does

Orchestrates the AI-powered data pipeline by coordinating parallel AI enrichment tasks (Comprehend, SageMaker) and merging results. Phase 4 implements a minimal Pass state to validate EventBridge integration; Phase 5+ expands to actual Lambda task orchestration.

## Why Step Functions?

**Architecture Decision Justification:**
- **Visual Workflow Management**: State machine provides graphical representation of pipeline flow
- **Built-in Error Handling**: Retry policies and error catching without custom code
- **Parallel Execution**: Fan-out to multiple AI services simultaneously, improving throughput
- **Serverless Orchestration**: No infrastructure to manage, pay-per-execution pricing
- **Audit Trail**: CloudWatch Logs capture every state transition for debugging

**Cost Consideration**: At $0.025 per 1,000 state transitions, even 10,000 monthly batch uploads cost only $0.25 - negligible for the orchestration value provided.

## Resources Created

- **Step Functions State Machine** - Orchestrates pipeline execution with Amazon States Language (ASL)
- **IAM Execution Role** - Allows state machine to invoke AWS services (currently CloudWatch Logs only)
- **CloudWatch Log Group** - Captures execution logs with ALL level detail for dev debugging
- **IAM Policy for Logging** - Grants state machine permissions to write CloudWatch Logs

## Phase 4 Scope

**What's Included NOW:**
- Minimal Pass state (no actual processing, just validates event delivery)
- CloudWatch Logs integration (execution visibility)
- IAM role with least-privilege permissions (CloudWatch Logs only)

**What's Coming in Phase 5+:**
- Replace Pass state with Parallel state for AI enrichment
- Add Lambda task invocations (Comprehend, SageMaker)
- Error handling (Retry, Catch blocks)
- Merge Lambda for DynamoDB writes

## Usage Example

```hcl
module "step_functions" {
  source = "../../modules/step_functions"

  # Required variables
  environment  = "dev"
  project_name = "ai-dp"
  aws_region   = "us-west-1"

  # Optional variables (defaults shown)
  log_retention_days = 7      # 7 days for dev, increase for prod
  log_level          = "ALL"  # ALL, ERROR, FATAL, or OFF

  # Additional tags (merged with resource-specific tags)
  tags = {}
}
```

## Outputs

```hcl
# For EventBridge target configuration (Task 2)
module.step_functions.state_machine_arn

# For CloudWatch Logs testing
module.step_functions.log_group_name

# For Terraform resource references
module.step_functions.state_machine_id
```

## Testing

### Manual Testing via AWS Console (Phase 4)

```powershell
# 1. Deploy the module (requires wiring in envs/dev/main.tf - Task 3)
terraform -chdir=envs/dev apply

# 2. Navigate to AWS Console
# - Service: Step Functions
# - Find: ai-dp-dev-orchestrator
# - Click: "Start execution"

# 3. Input test event (minimal JSON)
{}

# 4. Verify execution succeeds
# Expected output:
{
  "processing_result": {
    "message": "Event received successfully",
    "phase": "4-complete",
    "next_steps": "Add Lambda tasks in Phase 5"
  }
}

# 5. Check CloudWatch Logs
# - Navigate to: CloudWatch → Log groups
# - Find: /aws/states/ai-dp-dev-orchestrator
# - Verify: Execution logs appear with detailed state transitions
```

### CLI Testing

```powershell
# List state machines
aws stepfunctions list-state-machines

# Start execution
aws stepfunctions start-execution `
  --state-machine-arn <state-machine-arn> `
  --input '{}'

# View execution history
aws stepfunctions get-execution-history `
  --execution-arn <execution-arn>

# Tail CloudWatch Logs
aws logs tail /aws/states/ai-dp-dev-orchestrator --follow
```

## Key Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | - | Environment name (dev, stg, prod) - validated |
| `project_name` | string | - | Project name for resource naming |
| `aws_region` | string | - | AWS region for resources |
| `log_retention_days` | number | `7` | CloudWatch log retention (days) - validated against AWS valid values |
| `log_level` | string | `"ALL"` | Step Functions log level (ALL, ERROR, FATAL, OFF) |
| `tags` | map(string) | `{}` | Additional tags merged with resource-specific tags |

## Amazon States Language (ASL) Explanation

**Current Definition (Phase 4):**
```json
{
  "Comment": "Phase 4: Minimal orchestration - validates EventBridge integration",
  "StartAt": "ReceiveEvent",
  "States": {
    "ReceiveEvent": {
      "Type": "Pass",
      "Comment": "Placeholder state - accepts S3 event, no processing yet",
      "Result": {
        "message": "Event received successfully",
        "phase": "4-complete",
        "next_steps": "Add Lambda tasks in Phase 5"
      },
      "ResultPath": "$.processing_result",
      "End": true
    }
  }
}
```

**ASL Concepts:**
- `StartAt` - First state to execute (`ReceiveEvent`)
- `Type: Pass` - No-op state that passes input to output (testing integration)
- `Result` - Static JSON data injected into output
- `ResultPath` - Where to store Result in output (`$.processing_result` merges with input)
- `End: true` - Marks this as the final state

**Future Expansion (Phase 5+):**
```json
{
  "StartAt": "Parallel_AI_Enrichment",
  "States": {
    "Parallel_AI_Enrichment": {
      "Type": "Parallel",
      "Branches": [
        {"StartAt": "Comprehend_Sentiment", "States": {...}},
        {"StartAt": "SageMaker_Anomaly", "States": {...}}
      ],
      "Next": "Merge_Results"
    },
    "Merge_Results": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:ai-dp-dev-merge",
      "End": true
    }
  }
}
```

## Security

**IAM Role Trust Policy:**
- Allows `states.amazonaws.com` to assume role
- No additional conditions (Phase 4 scope)
- Future: Add confused deputy protection for production

**IAM Permissions (Current - Phase 4):**
- CloudWatch Logs: `logs:CreateLogDelivery`, `logs:PutResourcePolicy`, etc.
- **No service invocation permissions** - Pass state doesn't invoke external services

**IAM Permissions (Future - Phase 5+):**
- Lambda: `lambda:InvokeFunction` (scoped to specific function ARNs)
- S3: `s3:GetObject`, `s3:PutObject` (scoped to data lake bucket)
- DynamoDB: `dynamodb:PutItem` (scoped to hot store table)

**Least Privilege Principle**: Only permissions needed for current phase are granted. Future permissions added incrementally as tasks are added to state machine.

## Interview Talking Points

### Q: Why did you choose Step Functions for orchestration?

> "I need to coordinate multiple AWS AI services (Comprehend for sentiment analysis, SageMaker for anomaly detection) in parallel, then merge results into DynamoDB and S3. Step Functions provides visual workflow management and built-in error handling without writing orchestration logic in code. The declarative Amazon States Language makes the pipeline easy to understand, modify, and debug."

### Q: Why start with a Pass state instead of implementing the full pipeline?

> "I'm following an incremental development approach. Phase 4 validates the EventBridge integration with a minimal Pass state - no processing, just proof that S3 uploads trigger the state machine. Once proven, Phase 5 adds actual Lambda tasks. This prevents debugging integration issues AND business logic simultaneously. It's easier to troubleshoot one thing at a time."

### Q: How do you handle errors in Step Functions?

> "Step Functions provides built-in error handling with Retry and Catch blocks. In Phase 5+, I'll add retry policies for transient failures (like Lambda throttling) and Catch blocks to route failed tasks to a fallback state or error notification. For now, the Pass state can't fail, but the architecture is ready for error handling when I add real tasks."

### Q: What's the cost of using Step Functions?

> "Step Functions costs $0.025 per 1,000 state transitions. With my current Pass state (2 transitions: start + end), each execution costs $0.00005. Even scaling to 10,000 batch uploads per month, that's only $0.50. For production with more complex workflows (5-10 states), cost might reach $2-5/month for the same volume - still negligible compared to the orchestration value and reduced development time."

### Q: How do you monitor Step Functions executions?

> "I've configured CloudWatch Logs with log level ALL for dev, which captures every state transition, input/output data, and execution metadata. I can view real-time execution graphs in the Step Functions console, set CloudWatch alarms on execution failures, and query logs with CloudWatch Insights. For production, I'd reduce log level to ERROR to save costs while maintaining visibility into failures."

### Q: How would you handle long-running tasks in this pipeline?

> "Step Functions supports two workflow types: Standard (long-running, up to 1 year) and Express (high-throughput, max 5 minutes). For this data pipeline, I'm using Standard workflows because AI enrichment tasks can take minutes. If I needed faster processing for high-volume streaming, I'd switch to Express workflows and implement a different error handling strategy (since Express doesn't support visual debugging of individual executions)."

## Next Steps (After Task 1)

1. **Task 2**: Add EventBridge target configuration to `modules/ingestion_stream/`
2. **Task 3**: Wire Step Functions module in `envs/dev/main.tf`
3. **Task 4**: Integration testing (S3 upload → EventBridge → Step Functions → SUCCESS)
4. **Phase 5**: Replace Pass state with Parallel Lambda tasks for AI enrichment

## Resources

- [AWS Step Functions Documentation](https://docs.aws.amazon.com/step-functions/)
- [Amazon States Language Specification](https://states-language.net/spec.html)
- [Terraform aws_sfn_state_machine Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine)
- [Step Functions Best Practices](https://docs.aws.amazon.com/step-functions/latest/dg/bp-express.html)
