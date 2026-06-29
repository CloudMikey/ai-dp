---
name: comment-quality-improvements
description: Codebase comment quality audit and improvements completed 2026-06-07
metadata:
  type: project
---

## Comment Quality Audit & Improvements Complete ✅

**Date completed:** 2026-06-07  
**Impact:** Transformed comments from 7.7% density (456 lines) to recruiter-grade quality

### What Was Done

**1. Removed Decorative Headers**
- Eliminated ~100+ lines of decorator headers (`#--------- Text ---------#`) from 49 Terraform files
- Pattern was eliminating noise without adding value
- Result: Code feels cleaner, more professional

**2. Removed Redundant Comments**
- Eliminated comments that just restate what the code name already says
  - ❌ "Main S3 bucket for storing Terraform state files" (resource name is clear)
  - ❌ "Trust policy: Allow Lambda service to assume role" (code shows this)
- Kept comments that explain **WHY** decisions were made

**3. Enhanced IAM Comments Across Modules**
- **ingestion_stream/iam.tf:** Explains direct API Gateway writes (lower latency, cost vs Lambda proxy)
- **orchestration/iam.tf:** Clarifies data flow (reads Comprehend → writes to DynamoDB + S3)
- **step_functions/iam.tf:** Specific API actions (DetectSentiment + DetectEntities), execution context

**4. Shortened Verbose Comments**
- **Before:** "Covers S3 GetObject + 3x DynamoDB/S3 writes + Step Functions response; load test P95=2044ms well within limit"
- **After:** "Load test P95=2044ms; S3 + DynamoDB writes"
- Kept the valuable metrics, removed the prose

### Recruiter-Grade Comment Patterns Implemented

✅ **Comments explain WHY, not WHAT**
- Why direct S3 writes? (efficiency vs Lambda proxy)
- Why no read from processed/? (prevents circular dependencies)
- Why 30-day TTL? (cost control)

✅ **Security decisions justified**
- "Wildcard required by AWS for log delivery setup" + AWS documentation reference
- "PutItem only; no Scan/Query/GetItem for security"
- Explains tradeoffs, not just enforces them

✅ **Real metrics, not guesses**
- "Load test P95=2044ms well within 60s limit"
- Shows validation, not assumptions

✅ **Data flow context**
- "Reads raw/ (batch ingestion entry point for AI enrichment)"
- "Writes to DynamoDB (real-time) + S3 (historical)"
- Shows architectural thinking

✅ **Concise & scannable**
- Most comments are 1-2 lines
- No paragraphs or excessive documentation

### Files Updated

**Documentation:**
- CLAUDE.md — Removed decorator header recommendation
- .claude/agents/portfolio.md — Updated example patterns
- docs/templates/coding-rules-template.md — Changed guidance away from decorators

**Module IAM Files (Enhanced):**
- modules/ingestion_stream/iam.tf
- modules/orchestration/iam.tf
- modules/step_functions/iam.tf

**Module Main Files (Enhanced):**
- modules/orchestration/main.tf (tightened timeout/memory comments)
- modules/step_functions/main.tf (added log group purpose, removed "Phase 6" jargon)

### Key Learnings for Portfolio Recruiters

1. **Comment density is a quality signal:**
   - Too high (>15%) = code isn't self-documenting
   - Too low (<3%) = missing architectural context
   - Sweet spot: **5-10% for IaC, 10-15% for complex logic**

2. **What makes a good IaC comment:**
   - Explains the CONSTRAINT (AWS limitation, performance requirement)
   - References REALITY (load test P95, actual error fixed)
   - Shows SECURITY THINKING (least privilege, tradeoff justified)
   - Provides CONTEXT (this reads from raw/, writes to both stores)

3. **What recruiters interpret from comments:**
   - References to bug fixes → "They debugged real problems"
   - Metrics + validation → "They test their assumptions"
   - Security justifications → "They think about tradeoffs"
   - Internal jargon → "Code isn't interview-ready"

### Result

Portfolio codebase now signals:
- ✅ Professional, clean code (no decorators, no noise)
- ✅ Production thinking (cost, reliability, security)
- ✅ Real debugging experience (Athena JSON serialization, DynamoDB TTL patterns)
- ✅ Interview-ready explanations (can talk through WHY for every significant decision)

