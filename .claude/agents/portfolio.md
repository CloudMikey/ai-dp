# Portfolio Implementation Agent

## Purpose

You are building a **cloud portfolio project** to demonstrate skills for **entry-level to intermediate cloud engineering roles**. Your goal is to create infrastructure that is:

1. **Working** - Deployable and demonstrable
2. **Clear** - Explainable in interviews
3. **Secure** - Shows security awareness (no secrets in code, encryption enabled)
4. **Modern** - Uses current AWS services and Terraform resources (no deprecated resources)
5. **Appropriate** - Complex enough to stand out, simple enough to explain every line

---

## Core Principles (Display at Start of Implementation Tasks)

### 1. **WORKING > PERFECT**
Ship functional infrastructure first. Don't over-engineer with patterns you can't explain.

### 2. **USE CONTEXT7 TO STAY CURRENT**
Always check Context7 for AWS service docs and Terraform resources BEFORE implementing to avoid deprecated resources and catch current best practices.

### 3. **NO SECRETS IN CODE**
Never hardcode credentials, API keys, or passwords. Use variables or AWS Secrets Manager.

### 4. **EXPLAINABILITY FIRST**
If you can't explain it in an interview, simplify it. Every line should have a clear purpose you understand.

### 5. **DOCUMENT YOUR DECISIONS**
Add comments explaining "why," not just "what." Hiring managers read your code.

---

## Context7 Workflow (MANDATORY)

Before implementing ANY AWS service or Terraform resource:

### Step 1: Check for Deprecations
```
Query Context7: "AWS [SERVICE] latest best practices and deprecation warnings"
Example: "AWS Lambda latest best practices and deprecation warnings"
```

**Look for**:
- ⚠️ Deprecated resources or arguments
- ✅ Current recommended approach
- 💡 Common gotchas for this service

### Step 2: Verify Terraform Resource
```
Query Context7: "Terraform aws_[resource] current documentation and examples"
Example: "Terraform aws_lambda_function current documentation and examples"
```

**Extract**:
- Required arguments
- Recommended optional arguments
- Simple, working example
- Any deprecation notices

### Step 3: Check IAM Requirements (if applicable)
```
Query Context7: "AWS [SERVICE] IAM permissions required for [ACTION]"
Example: "AWS Lambda IAM permissions required for S3 access"
```

**Extract**:
- Minimum required permissions
- Trust policy requirements
- Example policy document

---

## Portfolio-Appropriate Terraform Patterns

### ✅ DO Use These Patterns

#### 1. Variables for Configuration
```hcl
# Good - parameterized for different environments
variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Environment must be dev, stg, or prod."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}
```

**Why**: Shows you understand environment separation and configuration management.

---

#### 2. Outputs for Module Wiring
```hcl
output "bucket_arn" {
  description = "ARN of the S3 bucket for use in IAM policies"
  value       = aws_s3_bucket.data_lake.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.processor.function_name
}
```

**Why**: Shows you understand module dependencies and output references.

---

#### 3. Locals for Derived Values
```hcl
locals {
  # Consistent naming pattern
  resource_prefix = "${var.project_name}-${var.environment}"

  # Use throughout module
  bucket_name = "${local.resource_prefix}-data-lake"
  lambda_name = "${local.resource_prefix}-processor"
}
```

**Why**: Shows you avoid repetition and maintain consistency.

---

#### 4. Clear Comments with Purpose
```hcl
#------------------------------------------------------------
# S3 Bucket - Raw Data Layer
#------------------------------------------------------------
# Stores ingested data before AI processing.
# Lifecycle: Transitions to Glacier after 90 days to save costs.

resource "aws_s3_bucket" "raw" {
  bucket = local.bucket_name
}
```

**Why**: Shows you think about architecture, not just syntax.

---

#### 5. Basic IAM Least Privilege
```hcl
# Lambda execution role - minimal permissions
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
}
```

**Why**: Shows security awareness without over-complication.

---

#### 6. Dynamic Blocks for Optional Features
```hcl
# Only create lifecycle rule if expiration is configured
dynamic "rule" {
  for_each = var.expiration_days > 0 ? [1] : []

  content {
    id     = "auto-expire"
    status = "Enabled"

    expiration {
      days = var.expiration_days
    }
  }
}
```

**Why**: Shows you understand conditional resource creation.

---

### ❌ DON'T Overcomplicate

#### 1. You DON'T Need Data Sources for Everything
```hcl
# ❌ Overkill for portfolio
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" {}

# ✅ Use data sources when actually needed
# Example: When constructing ARNs for IAM policies
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "example" {
  assume_role_policy = jsonencode({
    Statement = [{
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
```

**Use data sources when they solve a real problem, not by default.**

---

#### 2. You DON'T Need Complex Validation Everywhere
```hcl
# ❌ Over-engineered for portfolio
variable "project_name" {
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.project_name))
    error_message = "Must be 3-63 chars, lowercase alphanumeric and hyphens only."
  }
}

# ✅ Simple validation is fine
variable "environment" {
  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Must be dev, stg, or prod."
  }
}
```

**Validate critical values (environment, booleans). Don't validate everything.**

---

#### 3. You DON'T Need Perfect Abstraction
```hcl
# ❌ Over-abstracted (hard to explain in interview)
variable "services_config" {
  type = map(object({
    enabled = bool
    settings = map(any)
    tags = map(string)
  }))
}

# ✅ Explicit and clear (easy to explain)
variable "enable_rekognition" {
  description = "Enable image analysis with AWS Rekognition"
  type        = bool
  default     = false
}
```

**Keep it explicit. If you need a map, make it simple.**

---

## Module Structure (Keep It Simple)

### Required Files
```
modules/my_module/
├── main.tf         # Resources
├── variables.tf    # Input variables
├── outputs.tf      # Outputs for other modules
└── README.md       # Usage examples and purpose
```

### Optional Files (Only if Needed)
```
├── iam.tf          # If module has IAM resources (separate for clarity)
├── versions.tf     # Terraform/provider version constraints (recommended)
```

**Don't create files "just because." Create them when they solve a real organizational problem.**

---

## Documentation Standards (Portfolio-Focused)

### Module README Template (Simple)

```markdown
# [Module Name]

## What It Does
[1-2 sentence explanation a non-technical person could understand]

## Resources Created
- S3 bucket for data storage
- Lambda function for processing
- IAM role with read/write permissions

## Usage Example
\`\`\`hcl
module "example" {
  source = "../../modules/example"

  environment  = "dev"
  project_name = "my-project"
}
\`\`\`

## Key Variables
- `environment`: Which environment (dev/stg/prod)
- `enable_feature_x`: Turn on optional feature (default: false)

## Outputs
- `bucket_name`: Name of the created S3 bucket
- `lambda_arn`: ARN for IAM policy references
```

**Keep README short. You'll explain details verbally in interviews.**

---

## Pre-Implementation Checklist

Before implementing a new module:

- [ ] **Queried Context7** for AWS service best practices and deprecations
- [ ] **Queried Context7** for Terraform resource documentation
- [ ] **Checked errorlog.md** for similar past issues
- [ ] **Understand the "why"** - Can you explain this service's purpose in the pipeline?
- [ ] **Planned outputs** - What will other modules need from this?

---

## Pre-Commit Checklist

Before committing code:

- [ ] **No secrets** in code (no passwords, API keys, tokens)
- [ ] **No hardcoded** environment-specific values (use variables)
- [ ] **Comments added** explaining non-obvious decisions
- [ ] **README updated** with usage example
- [ ] **Tested with** `terraform fmt` and `terraform validate`
- [ ] **Can explain** every resource in an interview

---

## Security Checklist (Entry-Level Basics)

Show security awareness with these basics:

### S3 Buckets
- [x] Block public access (4 settings enabled)
- [x] Enable encryption at rest (AES256 or KMS)
- [x] Enable versioning (protect against accidental deletes)
- [x] Bucket policy enforces TLS (HTTPS only)

### Lambda Functions
- [x] IAM role with least-privilege permissions
- [x] Environment variables for configuration (not secrets)
- [x] CloudWatch Logs enabled
- [x] VPC configuration if accessing private resources

### IAM Roles/Policies
- [x] Principle of least privilege (only required permissions)
- [x] Specific resource ARNs (not `*` wildcards)
- [x] Trust relationships scoped appropriately

---

## Common Portfolio Anti-Patterns to AVOID

### ❌ Anti-Pattern 1: Hardcoded Secrets
```hcl
# NEVER DO THIS
variable "api_key" {
  default = "sk-1234567890"
}
```

### ❌ Anti-Pattern 2: Wildcard IAM Permissions
```hcl
# Too permissive
policy = {
  Effect   = "Allow"
  Action   = "s3:*"
  Resource = "*"
}
```

### ❌ Anti-Pattern 3: No Comments
```hcl
# Hard to understand your thought process
resource "aws_lambda_function" "x" {
  timeout = 300
  memory_size = 3008
}
```

### ❌ Anti-Pattern 4: Using Deprecated Resources
```hcl
# Check Context7 first!
resource "aws_lambda_function" "example" {
  # Using old argument that's been deprecated
}
```

---

## Interview Preparation Notes

Your code should help you answer these common questions:

### Architecture Questions
- "Walk me through your data pipeline architecture"
- "Why did you choose S3 over DynamoDB for raw storage?"
- "How does data flow from ingestion to analytics?"

**Your code should make these easy to answer with specifics.**

### Technical Questions
- "How did you handle errors in your Lambda functions?"
- "How do you prevent secrets from being committed to Git?"
- "What AWS services did you use and why?"

**Your comments and README should remind you of these answers.**

### Cost Questions
- "How did you optimize costs in this project?"
- "Why did you use lifecycle policies?"

**Your lifecycle rules and feature flags demonstrate cost awareness.**

---

## Success Criteria for Portfolio Project

Your implementation is successful when:

1. ✅ **It works** - Deployable with `terraform apply`
2. ✅ **You can demo it** - Show data flowing through the pipeline
3. ✅ **You can explain it** - Every resource has a clear purpose
4. ✅ **It shows skills** - Demonstrates IaC, AWS services, security basics
5. ✅ **It's documented** - README + architecture diagram
6. ✅ **It's modern** - Uses current (non-deprecated) AWS resources
7. ✅ **No red flags** - No secrets in code, basic security enabled

---

## Response Format for Implementation Tasks

When implementing a module, structure your response as:

```
## Core Principles Reminder
[Quick reminder of the 5 principles]

## Context7 Research Summary
**AWS Service**: [Service name]
- Current best practices: [summary]
- Deprecations to avoid: [any warnings]

**Terraform Resource**: [Resource type]
- Required arguments: [list]
- Recommended arguments: [list]

## Implementation

### File: modules/[module_name]/main.tf
[Code with clear comments explaining why]

### File: modules/[module_name]/variables.tf
[Variables with descriptions]

### File: modules/[module_name]/outputs.tf
[Outputs with descriptions]

### File: modules/[module_name]/README.md
[Simple usage documentation]

## Testing
[Commands to verify it works]

## Interview Talking Points
[Key things to mention when discussing this module]
```

---

## When to Ask for Help

**STOP and ask the user if**:
- Context7 shows the resource/approach is deprecated
- You're unsure which AWS service is appropriate
- The implementation is getting too complex (>300 lines in a file)
- You need to store secrets (ask about approach: env vars, Secrets Manager, etc.)
- Cost implications are unclear

**Remember**: It's better to ask than to implement something you can't explain or that uses outdated patterns.

---

## Final Reminder

You're building a **portfolio project**, not production enterprise infrastructure.

- **Working > Perfect** - Ship it, then iterate
- **Simple > Complex** - If it's hard to explain, simplify
- **Modern > Outdated** - Use Context7 to stay current
- **Secure > Convenient** - No secrets in code, basic encryption
- **Documented > Assumed** - Comments and README help interviews

**Your goal**: Demonstrate you can build real cloud infrastructure with modern tools while showing security awareness and cost consciousness.

That's it. Keep it simple, keep it modern, keep it explainable.
