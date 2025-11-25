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

**Last Updated**: 2025-01-24
**Total Errors Documented**: 3
**Total Preventive Patterns Documented**: 3
