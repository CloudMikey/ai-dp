---
description: Generate a manual implementation guide for a phase using realistic cloud engineer workflow
---

Create a manual coding guide for **{{phase_name}}** following the realistic cloud engineer workflow pattern.

**Output Location:** `Z:\CODE\Notes\Manual\phase-{{phase_number}}-{{slug}}-manual-guide.md`

**Requirements:**
1. ✅ Realistic workflow - switch between files as needed (like real development)
2. ✅ Variables created WHEN NEEDED (not all upfront)
3. ✅ Resources built incrementally (one at a time in order)
4. ✅ Simple sentence tasks with bullet points
5. ✅ Specific resource configurations listed (e.g., "Create resource 'aws_iam_role'. Config needed: name, assume_role_policy")
6. ✅ Include ALL terminal commands needed
7. ✅ File switching annotations ("Still in main.tf", "Switch to variables.tf", "Back to main.tf")
8. ✅ Notices when variables don't exist yet (⚠️ Notice: You referenced variables that don't exist yet)
9. ✅ Confirmations when no new variables needed (✅ No new variables needed)
10. ✅ Testing/verification steps at the end

**Workflow Pattern (follow exactly like phases 0-4):**

**Pattern 1: Start with code, then infrastructure**
- Example: Write Lambda Python code first, then create Terraform resources

**Pattern 2: Variables created when needed**
```
Step X: Create locals block
  - locals { bucket_name = "${var.project_name}-..." }
  ⚠️ Notice: Referenced variables that don't exist yet

Step X+1: Switch to variables.tf - Create Variables
  - variable "project_name" { ... }
```

**Pattern 3: Incremental resource building**
```
Step X: Still in main.tf - Create S3 Bucket
Step X+1: Still in main.tf - Add Versioning
  ✅ No new variables needed
```

**Pattern 4: IAM in separate file (when applicable)**
```
Step X: Switch to iam.tf - Create IAM Role
Step X+1: Still in iam.tf - Create IAM Policy
Step X+2: Back to main.tf - Reference IAM role
```

**Pattern 5: Wire module to environment**
```
Step X: Switch to Dev Environment - Wire Module
  File: envs/dev/main.tf
  - module "new_module" { source = "...", ... }

Step X+1: Switch to Dev Outputs - Expose Outputs
  File: envs/dev/outputs.tf
  - output "new_output" { value = module.new_module.output }
```

**Pattern 6: Deploy and test**
```
Step X: Validate and Deploy
  - terraform fmt, init, validate, plan, apply

Step X+1: Verify Deployment (AWS CLI commands)
Step X+2: Test Functionality (test data, verify outputs)
```

**Annotation Markers to Use:**
- **⚠️ Notice:** When variables/resources don't exist yet
- **✅ No new variables needed:** When resource uses existing variables
- **✅ Confirmed:** When verification succeeds
- **💡 Tip/Note:** Helpful explanation or context
- **🔧 If errors occur:** Troubleshooting guidance
- **📍 Location:** Where to add code in existing files
- **🤔 Engineer's Choice:** When multiple valid approaches exist
- **🏗️ Best Practice:** Industry-standard approaches
- **⚠️ Common Mistake:** Things to avoid

**IMPORTANT: Include Realistic Engineer Practices**

Add these throughout the guide where relevant:

1. **Decision Points - Offer Options:**
   - When multiple valid approaches exist, show both options
   - Explain pros/cons of each
   - Recommend which to use for this project
   - Example: "On-Demand vs Provisioned billing", "Least-privilege vs wildcard IAM"

2. **Check Prerequisites First:**
   - Before creating dependent resources, verify dependencies exist
   - Example: Check if module outputs are available before wiring modules
   - Use terminal commands to verify

3. **Start Simple, Add Complexity Later:**
   - Example: Pass state in Step Functions before adding AI tasks
   - Explain why (test infrastructure first, debug separately)

4. **Naming Conventions:**
   - Show the project's naming pattern
   - Explain why it's structured that way
   - Example: `{project}-{environment}-{resource}` format

5. **Resource Sizing Considerations:**
   - Explain starting values (Lambda 256MB, Kinesis 1 shard)
   - When to increase (monitoring metrics)
   - Cost implications

6. **Security Trade-offs:**
   - Highlight least-privilege IAM approach
   - Explain why wildcards are faster but less secure
   - Show this project uses least-privilege (portfolio best practice)

7. **Common Mistakes to Highlight:**
   - Hardcoding values instead of using variables
   - Not validating early (terraform fmt/validate)
   - Missing dependencies

8. **Validation After Major Changes:**
   - Run terraform fmt/validate after each major resource
   - Don't wait until the end

9. **Local Testing When Possible:**
   - Test Lambda functions locally before deploying (optional)
   - Test Step Functions definitions with Step Functions Local (optional)

10. **When to Refactor:**
    - File exceeds 300 lines
    - Logic duplicated 3+ times
    - Don't over-engineer early

**Document Structure:**
```markdown
# Phase [X]: [Name] - Manual Coding Guide
## Realistic Cloud Engineer Workflow

## Overview
[Brief description]

**What you'll build:** [One-line summary]

---

## Step 1: [Action]
### File: `path/to/file`
#### [What to create]
- **Type**: [resource/variable/etc]
- **Config needed**:
  - param1 = value1
  - param2 = value2

---

[Continue with numbered steps, file switching, etc.]

---

## Phase [X] Complete ✅

**What you built:**
1. ✅ [Item]
...

**Key Learning:**
- [Lesson]
...

**Next Phase**: Phase [X+1]
```

**Reference Examples:**
- Phase 0: Bootstrap (basic pattern)
- Phase 1: Data Lake (dynamic blocks, lifecycle rules)
- Phase 2: Streaming (Lambda code first, then Terraform)
- Phase 3: EventBridge (adding to existing module)
- Phase 4: Step Functions (separate iam.tf file, ASL JSON first)

**Concrete Examples - How to Show Engineer Practices:**

Example 1: Decision Point
```
## Step X: Configure DynamoDB Billing Mode

🤔 Engineer's Choice:

Option A: On-Demand (Recommended)
- Best for: Unpredictable workloads, dev/test
- Cost: Pay per request
- Use when: Starting out, variable traffic

Option B: Provisioned Capacity
- Best for: Predictable workloads, production
- Cost: Fixed hourly rate
- Use when: Known traffic patterns

**This project uses:** On-Demand (portfolio project, easier to explain)
```

Example 2: Best Practice
```
## Step Y: Configure IAM Permissions

🏗️ Best Practice: Least-Privilege IAM

- Config needed:
  - resources = [var.raw_bucket_arn]  # Scoped to specific prefix

⚠️ Common Mistake:
❌ resources = ["*"]  # Too permissive
✅ resources = [var.raw_bucket_arn]  # Least-privilege
```

Example 3: Resource Sizing
```
## Step Z: Configure Lambda Memory

💡 Starting Configuration:
- memory_size = 256  # Good default
- timeout = 60

When to increase:
- Duration approaching 60s (check CloudWatch)
- Memory utilization > 80%

Cost tip: More memory = faster CPU = potentially lower cost
```

**Phase Details:**
{{phase_details}}
