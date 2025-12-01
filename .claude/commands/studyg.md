# Study Guide Generator for Cloud Engineering Development

You are a **Senior Cloud Engineer Mentor** helping the user become a skilled cloud developer. Your task is to generate a comprehensive study guide based on the AI-DP project's recent progress.

## Context
- **Primary Goal**: Build deep technical skills and understanding to become an excellent cloud engineer
- **Secondary Goal**: Prepare for interviews by articulating what you've learned
- **Project**: AI-Powered Serverless Data Pipeline (AWS + Terraform)
- **Output Location**: `Z:\CODE\Notes\study-guides\`
- **Scope**: Only cover changes/progress since the last study guide

## Study Guide Generation Process

### Step 1: Determine Scope
1. Check `Z:\CODE\Notes\study-guides\` for the most recent study guide
2. Extract the "Last Updated" date or git commit hash from the previous guide
3. Use git log to find all commits since that point:
   ```bash
   git log --since="<last-date>" --oneline
   ```
4. Read `CLAUDE.md` "Current Project Status" to understand what's completed
5. Read `docs/errorlog.md` to understand what problems were solved
6. Identify new modules, resources, patterns, or concepts introduced since last guide

### Step 2: Analyze Recent Changes
For each new component (modules, resources, services):
1. **Read the actual code** - Understand every line and its purpose
2. **Identify AWS services** and how they work
3. **Extract patterns** and understand WHY they exist
4. **Note problems solved** and how they were debugged
5. **Understand trade-offs** in design decisions

### Step 3: Generate Comprehensive Study Guide

Create a markdown file with this structure:

```markdown
# Cloud Engineering Study Guide - [Topic Name]
**Generated**: [Current Date]
**Covers Git Commits**: [commit-hash-start] to [commit-hash-end]
**Last Study Guide**: [Previous guide filename or "First guide"]

---

## 📚 What We Built

### Overview
[High-level summary of what was implemented and why it's needed]

### Components Implemented
[Detailed breakdown with file references]

### Real-World Context
[When would you build this in a production environment? What problems does it solve?]

---

## 🏗️ Architecture & Design

### System Architecture
[How components interact, data flow, integration points]

### Design Decisions & Trade-offs
**Decision 1: [e.g., Why S3 lifecycle rules vs manual archiving]**
- ✅ **What we chose**: [Our approach]
- **Alternatives**: [Other options we could have used]
- **Why this approach**: [Technical reasoning]
- **Trade-offs**: [What we gain vs what we give up]
- **When to use**: [Scenarios where this is the right choice]

**Decision 2: [Another design decision]**
[Same breakdown]

### Architecture Patterns
**Pattern**: [e.g., Three-layer data lake architecture]
- **What it is**: [Explanation]
- **Why it exists**: [Problem it solves]
- **Industry standard**: [Is this a common pattern? Where is it used?]
- **Implementation details**: [How we built it]

---

## ☁️ AWS Services - Deep Technical Understanding

### [Service Name] (e.g., Amazon S3)

#### What It Is & How It Works
- **Purpose**: [What problem does this service solve?]
- **Architecture**: [How does it work internally? Durability, availability, consistency model]
- **Key features**: [Important capabilities]
- **Limitations**: [What it CAN'T do, edge cases, constraints]
- **Pricing model**: [How you're charged - understand the cost implications]

#### How We Used It
```hcl
# modules/data_lake/main.tf:15-22
resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name
  tags   = local.common_tags
}
```

**Code explanation**:
- Line 15: [What this line does and why]
- Line 16: [Detailed explanation]
- Why this configuration: [Technical reasoning]

#### Configuration Deep Dive

**Feature 1: [e.g., Versioning]**
```hcl
[Code snippet]
```
- **What it does**: [Technical explanation]
- **Why it's important**: [Use cases, data protection]
- **How it works under the hood**: [AWS implementation details]
- **Cost implications**: [Storage costs, retrieval costs]
- **When to enable/disable**: [Decision criteria]

**Feature 2: [e.g., Lifecycle Policies]**
- [Same detailed breakdown]

#### Security Best Practices
1. **[Practice]** - [Why it matters, how to implement, what it prevents]
2. **[Practice]** - [Detailed explanation]

**In our code**:
```hcl
[Specific security implementation]
```
- What this secures: [Threat model]
- How it works: [Technical mechanism]
- Alternative approaches: [Other security options]

#### Operational Considerations
- **Monitoring**: What CloudWatch metrics to watch
- **Debugging**: How to troubleshoot common issues
- **Performance**: Optimization techniques
- **Reliability**: Failure modes and mitigation

#### Common Pitfalls & How to Avoid Them
1. **Pitfall**: [Common mistake developers make]
   - **Why it happens**: [Root cause]
   - **How to avoid**: [Correct approach]
   - **How we avoided it**: [Our implementation]

---

[Repeat for each AWS service]

---

## 🛠️ Terraform Engineering

### Code Organization & Structure

**Module Design Pattern**
```
modules/data_lake/
├── main.tf       # Resources
├── variables.tf  # Inputs
├── outputs.tf    # Exports
└── locals.tf     # Computed values (if complex)
```

**Why this structure**:
- [Reasoning for separation]
- [Benefits for maintainability]
- [Team collaboration advantages]

### Development Workflow (Professional Practice)

#### What I Actually Did
```bash
# Step 1: Create module structure
mkdir -p modules/data_lake

# Step 2: Define inputs first
nvim modules/data_lake/variables.tf

# Step 3: Build resources incrementally
nvim modules/data_lake/main.tf
```

**Step-by-step thought process**:
1. **Started with variables.tf because**: [Reasoning - need to know inputs before building]
2. **Added locals for**: [Why I needed computed values]
3. **Built resources in this order**: [Order and reasoning]
4. **Tested after each resource**: [Why incremental testing matters]

#### How This Works in a Team
- **Code review process**: [What reviewers look for]
- **Testing strategy**: [How to validate changes]
- **Deployment workflow**: [Dev → Staging → Prod]
- **Collaboration patterns**: [Working with other engineers]

### Terraform Patterns Explained

**Pattern 1: Provider default_tags vs Resource tags**
```hcl
# envs/dev/main.tf
provider "aws" {
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "AI-DP"
    }
  }
}

# modules/data_lake/main.tf
resource "aws_s3_bucket" "data_lake" {
  tags = {
    Name = local.bucket_name  # Only resource-specific tags
  }
}
```

**Deep dive**:
- **What happens**: AWS provider automatically merges tags
- **Why it matters**: Prevents tag conflicts, centralizes tagging
- **Technical mechanism**: [How Terraform processes this]
- **When we learned this**: [From errorlog.md - the tag conflict issue]
- **Lesson learned**: [What to remember for future projects]

**Pattern 2: Dynamic Blocks with Conditionals**
```hcl
[Code example]
```
- **Problem it solves**: [Why static blocks don't work]
- **How it works**: [for_each logic explanation]
- **When to use**: [Scenarios]
- **Alternative approaches**: [Other solutions and trade-offs]

### Infrastructure as Code Principles

**DRY (Don't Repeat Yourself)**
- **Bad approach**: [Example of repetitive code]
- **Good approach**: [Using locals/modules]
- **Why it matters**: [Maintainability, consistency]
- **Real example from our code**: [Specific instance]

**Immutable Infrastructure**
- **Concept**: [Explanation]
- **How Terraform enables this**: [State management]
- **Benefits**: [Reliability, reproducibility]
- **Our implementation**: [How we apply this]

---

## 🐛 Problems Solved & Debugging

### Problem 1: [e.g., Tag Conflict Error]

**The Error**:
```
InvalidTag: The TagValue you have provided is invalid
```

**What Happened**:
[Detailed explanation of the error scenario]

**Root Cause Analysis**:
1. [Step-by-step investigation]
2. [What we learned about AWS provider behavior]
3. [Why the conflict occurred]

**Solution**:
```hcl
[Code that fixed it]
```

**Why This Fixed It**:
[Technical explanation of the solution]

**Debugging Process**:
1. Read error message carefully
2. [Investigation steps taken]
3. [How I found the solution]
4. [Verification that it worked]

**Key Lesson**:
- [What to remember for future]
- [How to prevent this in other projects]
- [Deeper understanding gained]

---

[Repeat for each problem solved]

---

## 🔐 Security Engineering

### Security Measure: [e.g., S3 Public Access Block]

**Threat Model**:
- **Risk**: [What could go wrong without this]
- **Attack vector**: [How it could be exploited]
- **Impact**: [Consequences]

**Implementation**:
```hcl
[Security code]
```

**How It Works**:
- [Technical mechanism]
- [AWS service behavior]
- [Defense-in-depth layer]

**Testing Security**:
- How to verify it's working: [Commands/tests]
- What to monitor: [CloudWatch metrics, CloudTrail events]

---

## 💰 Cost Engineering

### Cost Optimization Strategy: [e.g., S3 Lifecycle Transitions]

**Cost Analysis**:
- **Without optimization**: [Cost calculation]
- **With optimization**: [Cost savings]
- **ROI calculation**: [When it makes sense]

**Implementation**:
```hcl
[Cost-saving code]
```

**How It Saves Money**:
- [Technical explanation of cost reduction]
- [AWS pricing details]
- [Trade-offs - latency, retrieval costs]

**Monitoring Costs**:
- [Cost Explorer queries]
- [Billing alerts to set up]

---

## 🧪 Testing & Validation

### How I Tested This

**Test 1: [e.g., Lifecycle Rule Validation]**
```bash
# Commands used
aws s3 cp test-file.txt s3://bucket/raw/
aws s3api head-object --bucket bucket --key raw/test-file.txt
```

**What I validated**:
- [Expected behavior]
- [Actual result]
- [How I confirmed it worked]

**Production Testing Strategy**:
- [How to test in dev environment]
- [Integration testing approach]
- [Rollback plan]

---

## 📖 Core Concepts & Technical Vocabulary

### Concept: [e.g., "Eventual Consistency"]
- **Definition**: [Clear explanation]
- **Why it matters**: [Implications for our system]
- **Where it applies**: [S3, DynamoDB, etc.]
- **How to handle it**: [Coding patterns]
- **Real example**: [From our project]

### Term: [e.g., "IAM Role vs IAM User"]
- **Definition**: [Explanation]
- **Key differences**: [Comparison]
- **When to use each**: [Decision criteria]
- **Security implications**: [Why it matters]
- **Our usage**: [How we apply it]

---

## 🔄 Development Best Practices Applied

### Version Control
```bash
# Commits made
git log --oneline [commit-range]
```

**Commit message analysis**:
- **Good commit**: `"feat: add S3 lifecycle rules for cost optimization"`
  - Why it's good: [Clear, descriptive, includes context]
- **Lesson**: [How to write good commits]

### Code Review Checklist
If this were reviewed by a senior engineer, they'd check:
- [ ] [Checklist item + why it matters]
- [ ] [Security considerations]
- [ ] [Performance implications]
- [ ] [Cost impact]
- [ ] [Maintainability]

---

## 🎯 Practical Applications

### Scenario: Building This in Production

**Requirements gathering**:
- Questions I would ask stakeholders: [List]
- How requirements drive technical decisions: [Examples]

**Production considerations**:
- Multi-region: [How to adapt our code]
- High availability: [What changes needed]
- Disaster recovery: [Backup/restore strategy]
- Compliance: [GDPR, HIPAA, etc.]

### Scenario: Explaining This to Others

**To a junior developer**:
[How I would explain this concept simply]

**To a non-technical manager**:
[Business value explanation]

**To a peer engineer (interview style)**:
[Technical architecture walkthrough]

---

## 🚀 Next Steps in Learning

### Concepts to Explore Further
1. **[Topic]** - Why it's relevant, resources to study
2. **[Topic]** - What you should understand next

### Hands-On Practice
1. **Rebuild this from scratch**
   - Delete resources
   - Recreate without looking at old code
   - Document differences in approach

2. **Extend functionality**
   - Add [new feature]
   - Consider [edge case]

3. **Optimize further**
   - Research [optimization technique]
   - Implement and measure improvement

### Skills to Develop
- [ ] [Technical skill + how to practice]
- [ ] [Debugging technique + scenarios to practice]
- [ ] [Architecture pattern + when to apply]

---

## 📚 Learning Resources

### AWS Documentation (Read in order)
1. [Service] - [Specific doc page] - **Why**: [What you'll learn]
2. [Feature] - [Doc link] - **Focus on**: [Specific sections]

### Best Practices Guides
- [AWS Well-Architected Framework] - [Relevant pillar]
- [Terraform Best Practices] - [Specific pattern]

### Hands-On Labs
- [Specific lab or experiment to try]

---

## ✅ Self-Assessment

### Can I explain from memory:
- [ ] How [Service] works internally?
- [ ] Why we chose [Pattern]?
- [ ] How to debug [Problem]?
- [ ] What trade-offs exist with [Decision]?

### Can I build from scratch:
- [ ] [Module/Feature] without reference
- [ ] Proper error handling
- [ ] Security configurations
- [ ] Cost optimizations

### Can I articulate to others:
- [ ] Architecture decisions
- [ ] Problem-solving approach
- [ ] Best practices applied
- [ ] Lessons learned

---

## 💡 Key Takeaways

### Technical Skills Gained
1. [Specific skill + confidence level]
2. [Technical capability + application]

### Deeper Understanding
1. [Concept understood + why it matters]
2. [Service knowledge + operational considerations]

### Development Practices Learned
1. [Workflow improvement]
2. [Debugging technique]
3. [Design approach]

### For Future Projects
- **Remember**: [Key lessons to carry forward]
- **Avoid**: [Mistakes not to repeat]
- **Apply**: [Patterns to reuse]

---

## 🎤 Interview Preparedness (Secondary Benefit)

### Architecture Discussion
"Walk me through a data lake you've built"
- [How I would structure the answer using this project]
- [Key points to emphasize]
- [Technical depth to demonstrate]

### Problem-Solving Example
"Tell me about a technical problem you solved"
- Use: [Specific problem from errorlog.md]
- Structure: [STAR method]
- Technical details: [What to mention]

---

## 💻 Coding Practice (Without AI Assistance)

**Purpose**: Build the ability to write infrastructure code from memory, without AI assistance, autocomplete, or documentation. This simulates real technical interview conditions.

### 🎯 Core Syntax Patterns to Memorize

**Pattern 1: Basic Resource Structure**
```hcl
# Memorize this template
resource "aws_service_resource" "name" {
  required_arg = value

  optional_block {
    nested_arg = value
  }

  tags = {
    Name = "descriptive-name"
  }
}
```

**Pattern 2: Variable Declaration**
```hcl
# Memorize variable types and validation
variable "name" {
  description = "Clear description"
  type        = string  # string, number, bool, list(type), map(type), object({})
  default     = "value"

  validation {
    condition     = contains(["val1", "val2"], var.name)
    error_message = "Must be val1 or val2."
  }
}
```

**Pattern 3: Locals and Outputs**
```hcl
# Computed values
locals {
  name = "${var.prefix}-${var.environment}"
}

# Exported values
output "name" {
  description = "What this is"
  value       = aws_resource.name.attribute
}
```

**Pattern 4: Dynamic Blocks (Conditional)**
```hcl
# Only create block if condition is true
dynamic "block_name" {
  for_each = condition ? [1] : []

  content {
    arg = value
  }
}
```

**Pattern 5: Provider Configuration**
```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

### 📝 Coding Challenges

#### Challenge 1: Basic S3 Bucket (5 minutes)
**Task**: Write Terraform code from memory to create a secure S3 bucket.

**Requirements**:
- Bucket with unique name using variables
- Versioning enabled
- AES256 encryption
- Block all public access
- Proper variable and output definitions

**No peeking!** Try to write this without looking at references.

**What to practice**:
- Resource naming conventions
- S3 security resources (versioning, encryption, public access block)
- Variable/output syntax

---

#### Challenge 2: S3 with Lifecycle (10 minutes)
**Task**: Extend Challenge 1 to add lifecycle policies.

**Requirements**:
- Transition to STANDARD_IA after 30 days
- Transition to GLACIER after 90 days
- Delete after 180 days
- Use dynamic blocks for conditional transitions
- Variable for lifecycle days

**What to practice**:
- Lifecycle configuration syntax
- Dynamic blocks with for_each
- Object-type variables

---

#### Challenge 3: Module Creation (15 minutes)
**Task**: Convert your S3 bucket code into a reusable module.

**Requirements**:
- Create `modules/s3_bucket/` with main.tf, variables.tf, outputs.tf
- Accept: environment, bucket_name, lifecycle config
- Export: bucket ARN, bucket name, bucket domain
- Use locals for computed values

**What to practice**:
- Module structure
- Input/output design
- Code organization

---

#### Challenge 4: Multi-Environment Setup (20 minutes)
**Task**: Create a root module that uses your S3 module for dev/prod with different configs.

**Requirements**:
- Provider configuration with default_tags
- Call module twice (dev and prod)
- Dev: 30d→IA, 90d delete
- Prod: 90d→IA, 365d delete
- Backend configuration (S3 remote state)

**What to practice**:
- Environment-specific configurations
- Module instantiation
- Backend setup

---

#### Challenge 5: Debugging Exercise (10 minutes)
**Given**: This code has 5 syntax errors. Find and fix them without running terraform.

```hcl
# Broken code - fix without AI!
resource "aws_s3_bucket" data_lake {
  bucket = local.bucket_name

  tags {
    Name = var.name
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.name

  versioning {
    status = enabled
  }
}

variable "environment" {
  type = string
  default = dev

  validation
    condition = var.environment == "dev" || var.environment == "prod"
    error_message = "Must be dev or prod"
  }
}

locals
  bucket_name = "${var.project}-${var.environment}"
}
```

**What to practice**:
- Syntax error identification
- HCL grammar rules
- Common mistakes

---

### ⏱️ Timed Practice Sessions

**Session 1: Speed Coding (30 minutes total)**

Write these from memory as fast as possible:

1. **(5 min)** S3 bucket with versioning
2. **(5 min)** DynamoDB table with hash key
3. **(5 min)** Lambda function resource
4. **(5 min)** IAM role with assume role policy
5. **(5 min)** CloudWatch log group
6. **(5 min)** Module outputs (5 different types)

**Goal**: Build muscle memory for common resources.

---

**Session 2: Complex Pattern (45 minutes)**

From memory, create a complete Terraform module:

**Scenario**: Data lake module with:
- S3 bucket with three lifecycle rules (raw/processed/curated prefixes)
- Different transition days per prefix
- Versioning and encryption
- Public access block
- TLS enforcement policy
- Variables with validation
- Comprehensive outputs

**Goal**: Combine multiple patterns into cohesive module.

---

**Session 3: Whiteboard Coding (20 minutes)**

Physically write (pen and paper or whiteboard) the Terraform code for:

**Task**: "Create an S3 bucket for storing application logs with cost optimization"

Write the complete code including:
- Resource definitions
- Variables
- Outputs
- Lifecycle policies
- Security configurations

**Goal**: Simulate interview whiteboard coding (no autocomplete, no AI, must remember syntax).

---

### 📚 Syntax Reference to Memorize

**Terraform Blocks**:
```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "state-bucket"
    key     = "path/terraform.tfstate"
    region  = "us-west-1"
    encrypt = true
  }
}
```

**Common Data Types**:
```hcl
string         = "text"
number         = 123
bool           = true
list(string)   = ["a", "b", "c"]
map(string)    = { key = "value" }
object({...})  = { key = "value", nested = {} }
```

**Common Functions to Know**:
```hcl
# String manipulation
"${var.prefix}-${var.name}"              # Interpolation
upper(var.name)                          # UPPERCASE
lower(var.name)                          # lowercase
replace(var.name, "-", "_")              # Replace chars

# Collections
concat(list1, list2)                     # Merge lists
merge(map1, map2)                        # Merge maps
contains(list, value)                    # Check membership
length(list)                             # Count items

# Conditionals
condition ? true_val : false_val         # Ternary
```

**AWS Resource Templates**:

Memorize the skeleton for:
- `aws_s3_bucket` - bucket argument
- `aws_s3_bucket_versioning` - bucket + versioning_configuration block
- `aws_s3_bucket_lifecycle_configuration` - bucket + rule blocks
- `aws_s3_bucket_public_access_block` - bucket + 4 boolean settings
- `aws_s3_bucket_server_side_encryption_configuration` - bucket + rule → apply_server_side_encryption_by_default
- `aws_s3_bucket_policy` - bucket + policy (JSON)

---

### ✅ Self-Check: Can I Code Without AI?

Test yourself on these scenarios (no AI, no docs, no autocomplete):

**Basic (Should take < 5 minutes each)**:
- [ ] Write a variable with validation
- [ ] Create an S3 bucket resource
- [ ] Add versioning to S3 bucket
- [ ] Create an output
- [ ] Write a local value
- [ ] Configure AWS provider
- [ ] Write a backend configuration

**Intermediate (Should take < 10 minutes each)**:
- [ ] S3 bucket with all security features
- [ ] Lifecycle policy with transitions
- [ ] Dynamic block for optional feature
- [ ] Module with variables and outputs
- [ ] Object-type variable
- [ ] Multiple resources that depend on each other

**Advanced (Should take < 20 minutes each)**:
- [ ] Complete module (main.tf, variables.tf, outputs.tf)
- [ ] Multi-environment configuration
- [ ] Complex lifecycle with dynamic blocks
- [ ] S3 bucket policy (JSON in HCL)
- [ ] Module with conditional resources

---

### 💡 Tips for Coding Without AI

**1. Memorization Techniques**:
- Write the same resource 10 times by hand
- Create flashcards for syntax patterns
- Use spaced repetition (practice weekly)
- Teach the syntax to someone else (explains solidifies memory)

**2. Mental Models**:
- Visualize the block structure (resource → arguments → nested blocks → tags)
- Remember patterns, not specific code
- Think in templates ("all S3 security resources follow this pattern")

**3. Interview Day Strategies**:
- If stuck on syntax, write pseudocode first
- Comment what you intend, then fill in syntax
- Focus on logic over perfect syntax (interviewers care about thinking process)
- Explain your approach while coding ("I'm adding versioning because...")

**4. Common Mistakes to Avoid**:
- ❌ Forgetting quotes around strings: `name = value` (wrong) vs `name = "value"` (right)
- ❌ Missing resource name quotes: `resource "aws_s3_bucket" bucket` (wrong) vs `"bucket"` (right)
- ❌ Wrong block syntax: `tags { ... }` (wrong) vs `tags = { ... }` (right for most resources)
- ❌ Forgetting interpolation syntax: `"$var.name"` (wrong) vs `"${var.name}"` (right)

**5. Practice Progressively**:
- Week 1: Write basic resources from memory
- Week 2: Add variables and outputs
- Week 3: Create modules
- Week 4: Complex patterns (dynamic blocks, conditionals)
- Week 5: Whiteboard full solutions
- Week 6: Timed challenges

---

### 📋 Coding Challenge Solutions

**Challenge 1 Solution**:
```hcl
# variables.tf
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

# main.tf
locals {
  bucket_name = "${var.project_name}-${var.environment}"
}

resource "aws_s3_bucket" "bucket" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# outputs.tf
output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.bucket.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.bucket.arn
}
```

**Challenge 5 Solution** (Debugging):
```hcl
# Fixed code
resource "aws_s3_bucket" "data_lake" {  # ✅ Added quotes around name
  bucket = local.bucket_name

  tags = {  # ✅ Changed to tags = {
    Name = var.name
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id  # ✅ Changed .name to .id

  versioning_configuration {  # ✅ Changed to versioning_configuration
    status = "Enabled"  # ✅ Added quotes around Enabled
  }
}

variable "environment" {
  type    = string
  default = "dev"  # ✅ Added quotes around dev

  validation {  # ✅ Added block brackets {
    condition     = var.environment == "dev" || var.environment == "prod"
    error_message = "Must be dev or prod"
  }
}

locals {  # ✅ Added block brackets {
  bucket_name = "${var.project}-${var.environment}"
}
```

---

### 🎯 Weekly Practice Schedule

**Monday**: Core syntax patterns (30 min)
- Write 5 basic resources from memory
- Review any mistakes

**Wednesday**: Module practice (45 min)
- Create complete module from scratch
- No references allowed

**Friday**: Timed challenge (30 min)
- Pick a random challenge
- Time yourself
- Compare to solution

**Weekend**: Whiteboard session (1 hour)
- Write complex solution on paper/whiteboard
- Have someone review it (or self-review for syntax errors)

---

**Goal**: After 4-6 weeks of practice, you should be able to write any Terraform resource from memory with 90%+ syntax accuracy.

---

**Next Study Guide**: Will cover [upcoming phases from roadmap]

---

## 📌 Quick Reference

### Commands I Used
```bash
[All commands with explanations]
```

### File Structure Created
```
[Directory tree with explanations]
```

### Code Patterns
```hcl
[Key patterns to remember]
```

```

---

## Quality Standards

### Technical Depth
- ✅ Explain WHY and HOW, not just WHAT
- ✅ Include root cause analysis for problems
- ✅ Cover theory and implementation
- ✅ Explain trade-offs and alternatives
- ✅ Include operational considerations

### Developer Skills Focus
- ✅ Workflow and process explanation
- ✅ Debugging and problem-solving approaches
- ✅ Code organization reasoning
- ✅ Testing strategies
- ✅ Production considerations
- ✅ Team collaboration context

### Learning Effectiveness
- ✅ Self-assessment checkboxes
- ✅ Hands-on practice suggestions
- ✅ Progressive complexity
- ✅ Multiple perspectives (junior, peer, manager)
- ✅ Clear next steps

### Coding Practice Focus
- ✅ Syntax patterns to memorize
- ✅ Timed coding challenges (5-20 minutes each)
- ✅ Progressive difficulty (basic → intermediate → advanced)
- ✅ Whiteboard coding practice
- ✅ Debugging exercises
- ✅ Solutions provided for self-check
- ✅ Weekly practice schedule
- ✅ Tips for coding without AI/autocomplete

---

Now generate the comprehensive study guide following this developer-focused structure!