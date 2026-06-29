---
name: iam-comment-patterns
description: Best IAM comment patterns for recruiter portfolios - security + clarity focus
metadata:
  type: feedback
---

## IAM Comment Patterns - What Works

**Applied to:** ingestion_stream, orchestration, step_functions modules  
**Result:** Comments now explain security decisions + architectural thinking

### Pattern 1: Role Purpose (Single Line)

✅ **Good:**
```hcl
# Merge Lambda: combines Comprehend outputs (sentiment + entities) into enriched records
```

Tells recruiter: What this role is for, what data it processes

---

### Pattern 2: Managed vs Inline Policy Tradeoff

✅ **Good:**
```hcl
# AWS managed policies handle standard permissions (logs, Kinesis stream reads)
# Inline policies below handle custom scopes (S3 raw/ only, DLQ only)
```

Tells recruiter: You understand the IAM design pattern, not just permission names

---

### Pattern 3: Security Boundaries

✅ **Good:**
```hcl
# Merge Lambda: reads Comprehend outputs (raw/) + writes enriched data to dual storage (DynamoDB + S3 curated/)
# Scoped: no read from processed/, no access to other buckets
```

Tells recruiter: You think about what permissions are NOT granted (least privilege)

---

### Pattern 4: Architecture Context in Permissions

✅ **Good:**
```hcl
# S3 write policy: processed/ (enriched data) + curated/ (pre-aggregated summary)
# Write only; no read from processed (prevents circular dependencies)
```

Tells recruiter: You understand the data pipeline, not just granting permissions

---

### Pattern 5: Specific API Actions (Not Wildcard)**

✅ **Good:**
```hcl
# Comprehend permissions for DetectSentiment + DetectEntities (managed policy from module variable)
```

Tells recruiter: You know which specific APIs are needed, not just service-level access

---

### Pattern 6: Security Exceptions with Justification

✅ **Excellent:**
```hcl
# Wildcard required by AWS for log delivery setup
# AWS does not support resource-level permissions for Step Functions logging
# Ref: https://docs.aws.amazon.com/step-functions/latest/dg/cw-logs.html
```

Tells recruiter: You researched the constraint, didn't just add wildcard blindly

---

### Pattern 7: Least-Privilege with Reason

✅ **Good:**
```hcl
# DynamoDB write-only (PutItem only; no Scan, Query, GetItem for security)
# 30-day TTL auto-cleanup prevents cost growth
```

Tells recruiter: You think about both security AND cost

---

### Pattern 8: Data Flow in Permission Scope

✅ **Good:**
```hcl
# S3 read from raw/ prefix (batch ingestion entry point for AI enrichment)

# Direct PutRecord is more efficient than Lambda proxy integration (lower latency, cost)
```

Tells recruiter: This permission isn't random; it fits the architecture

---

## What NOT to Do

❌ **Bad:**
```hcl
# Allows Lambda to read from S3
resource "aws_iam_role_policy" "s3_read" {
```

Why: "Allows" is obvious from the code. Doesn't explain WHY or WHERE.

---

❌ **Bad:**
```hcl
# Trust policy: Allow Lambda service to assume this role
assume_role_policy = jsonencode({
```

Why: Redundant with the code structure. Wastes space.

---

❌ **Bad:**
```hcl
# Required for Phase 7 implementation
# TODO: Revisit in Phase 8 when we refactor
```

Why: Internal jargon. Recruiter doesn't know your phases.

---

## Summary

When commenting IAM:

✅ **Explain the BOUNDARY** — What this role can/cannot do  
✅ **Show the CONTEXT** — Where does this fit in the data flow?  
✅ **Justify EXCEPTIONS** — Why does this have wildcard/elevated permissions?  
✅ **Reference REALITY** — "Load test showed", "Fixes X error", "AWS limitation"  
✅ **Think in LAYERS** — Managed for standard, inline for custom scopes

❌ Avoid vague "allows", "requires", "needed for"  
❌ Avoid internal project phases/TODOs  
❌ Avoid redundant explanations of what code already says  

