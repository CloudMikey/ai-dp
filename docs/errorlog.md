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

**Last Updated**: 2025-10-23
**Total Errors Documented**: 2
