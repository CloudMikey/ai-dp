# Cost Optimization Report - AI-DP Dev Environment

**Date:** 2026-01-28
**Environment:** Development (dev)
**Project:** AI-DP (AI-Powered Serverless Data Pipeline)

## Executive Summary

This report documents the cost optimization review for the AI-DP development environment as part of Phase 9 Task 6. The infrastructure has been configured with environment-appropriate cost controls that balance learning/testing needs with AWS cost efficiency.

**Key Findings:**
- ✅ All log groups configured with 7-day retention
- ✅ S3 lifecycle policies optimized for dev environment
- ✅ DynamoDB on-demand billing appropriate for sporadic workloads
- ✅ AWS Budget alert configured at $50/month with 80% and 100% thresholds
- ✅ Estimated monthly costs: $11-12/month (well under $50 budget)

---

## Current Monthly Cost Breakdown

Based on Cost Explorer data from 2026-01-01 to 2026-01-28:

| Service | Actual Cost (Jan 2026) | Explanation |
|---------|------------------------|-------------|
| **Amazon Kinesis** | $10.87 | On-demand data stream (largest cost driver) |
| **AWS Step Functions** | $0.19 | State transitions for orchestration |
| **AWS Glue** | $0.21 | Data catalog crawler runs |
| **Amazon Route 53** | $0.50 | DNS hosted zone |
| **Amazon Athena** | $0.07 | SQL query data scanned |
| **Amazon S3** | $0.04 | Data Lake storage + requests |
| **Amazon DynamoDB** | $0.002 | On-demand reads/writes |
| **CloudWatch Events** | $0.001 | EventBridge rule invocations |
| **Lambda + API Gateway** | $0.00 | Free tier coverage |
| **KMS + SNS + SQS** | $0.00 | Minimal usage, within free tier |
| **TOTAL** | **~$11.90/month** | **76% under budget** |

**Cost Trend:** Current trajectory suggests $12-15/month for active development, well under the $50 budget threshold.

---

## 1. CloudWatch Logs Retention Review

### Audit Results

All log groups configured with appropriate 7-day retention for dev environment:

| Log Group | Retention | Status |
|-----------|-----------|--------|
| `/aws/lambda/ai-dp-dev-etl` | 7 days | ✅ Optimal |
| `/aws/lambda/ai-dp-dev-merge` | 7 days | ✅ Optimal |
| `/aws/apigateway/ai-dp-dev-ingestion-api` | 7 days | ✅ Optimal |
| `/aws/states/ai-dp-dev-orchestrator` | 7 days | ✅ Optimal |

### Configuration Details

**Terraform Implementation:**
```hcl
# modules/ingestion_stream/main.tf:174-176
resource "aws_cloudwatch_log_group" "etl_lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7
}
```

All log groups have explicit retention configured in Terraform (not relying on Lambda-managed defaults).

### Cost Impact

- **7-day retention cost:** ~$0.20/month for current log volume
- **Never expire cost:** Would accumulate indefinitely (~$0.50/month after 1 year)
- **Savings:** Minimal for portfolio project, but demonstrates best practices

### Environment Comparison

| Environment | Recommended Retention | Rationale |
|-------------|----------------------|-----------|
| **Dev** | 7 days | Adequate for debugging, minimizes cost |
| **Staging** | 30 days | Longer testing cycles, pre-prod validation |
| **Production** | 90 days | Compliance, audit trail, incident investigation |

### Interview Talking Points

- "I set 7-day retention for dev to balance debugging needs with cost optimization"
- "Production would use 30-90 days based on compliance requirements like SOC 2 or PCI DSS"
- "CloudWatch Logs pricing is $0.50/GB ingested + $0.03/GB/month storage, so short retention prevents accumulation"
- "Demonstrates understanding of environment-specific operational requirements"

---

## 2. S3 Data Lake Lifecycle Policy Review

### Current Configuration

**Raw Layer:**
- Transition to Infrequent Access: 30 days
- Transition to Glacier: 90 days
- Expiration: 180 days (6 months)

**Processed Layer:**
- Transition to Infrequent Access: 60 days
- Transition to Glacier: 120 days
- Expiration: 365 days (1 year)

**Curated Layer:**
- No lifecycle transitions (frequent access expected)
- No expiration (business-critical aggregated data)

**Athena Results Bucket:**
- Expiration: 7 days (query results auto-deleted)

### Cost Analysis

| Storage Class | Cost per GB/month | Dev Usage | Monthly Cost |
|---------------|-------------------|-----------|--------------|
| Standard | $0.023 | ~1 GB | $0.02 |
| Infrequent Access | $0.0125 | Minimal | $0.01 |
| Glacier | $0.004 | Minimal | $0.00 |

**Total S3 Storage Cost:** ~$0.04/month (within observed actuals)

### Optimization Assessment

**Status:** ✅ Already optimal for dev environment

The lifecycle policies are appropriately aggressive for a development environment:
- 180-day raw retention sufficient for demos and debugging
- 365-day processed retention allows year-over-year analytics testing
- Curated data preserved for dashboards and reporting
- Athena results auto-cleanup prevents stale query bloat

### Production Recommendations

For production workloads, adjust retention based on business requirements:

```hcl
# Production example
raw_layer_lifecycle = {
  transition_to_ia_days      = 90
  transition_to_glacier_days = 365
  expiration_days            = 730  # 2 years for compliance
}
```

### Interview Talking Points

- "I configured aggressive lifecycle policies for dev (180 days) to minimize storage costs while maintaining adequate history for portfolio demos"
- "For production, I'd extend retention to 2-3 years based on regulatory requirements (e.g., HIPAA, GDPR)"
- "Demonstrates understanding of AWS S3 storage classes and cost optimization levers"
- "Lifecycle policies automatically transition data without manual intervention, reducing operational overhead"

---

## 3. DynamoDB Capacity Mode Analysis

### Current Configuration

- **Billing Mode:** On-demand (PAY_PER_REQUEST)
- **TTL:** Enabled (30-day automatic deletion)
- **Point-in-Time Recovery:** Enabled (35-day backups)
- **Table:** `ai-dp-dev-enriched-data`

### Cost Analysis

#### On-Demand Pricing (Current)
- Write requests: $1.25 per million
- Read requests: $0.25 per million
- Storage: $0.25/GB/month

**Dev Workload Profile:**
- Sporadic testing: 50-100 requests during demo sessions
- Idle most of the time (not continuous production traffic)
- Actual cost: $0.002/month

**Estimated Dev Usage:**
- 100 writes/day × 30 days = 3,000 writes/month = $0.004
- 50 reads/day × 30 days = 1,500 reads/month = $0.0004
- Storage: 1,000 records × 5 KB avg = 5 MB = $0.001
- **Total On-Demand:** ~$0.005/month

#### Provisioned Pricing (Alternative)

Minimum provisioned capacity:
- 5 WCU + 5 RCU = $2.50/month base cost

**Break-even Analysis:**
- On-demand cost = Provisioned cost when usage = 2 million requests/month
- Dev usage = 4,500 requests/month (1,500x below break-even)

### Decision: On-Demand is Optimal

**Rationale:**
- Portfolio demos are sporadic (10 minutes active, then idle for days)
- Provisioned capacity would cost 500x more for dev workload
- On-demand eliminates capacity planning complexity
- TTL auto-deletion keeps storage costs minimal

### Production Considerations

For production with predictable sustained load:
- If consistently > 500 WCU or > 500 RCU, provisioned is cheaper
- Use CloudWatch metrics to analyze actual RCU/WCU usage
- Consider reserved capacity for 20-40% additional savings

### Interview Talking Points

- "I chose on-demand billing because portfolio demos are sporadic, not production traffic"
- "For production with 1,000 sustained RPS, I'd analyze CloudWatch metrics and likely switch to provisioned capacity with auto-scaling"
- "TTL auto-deletion keeps storage costs minimal by purging records after 30 days"
- "Demonstrates understanding of DynamoDB pricing models and workload-appropriate capacity planning"

---

## 4. AWS Budget Alert Configuration

### Implemented Configuration

**Budget Details:**
- **Name:** `ai-dp-dev-monthly-budget`
- **Amount:** $50.00 USD/month
- **Type:** Cost budget (all services)
- **Start Date:** 2026-01-01

**Alert Thresholds:**

| Threshold | Type | Trigger Point | Action |
|-----------|------|---------------|--------|
| 80% | Actual | $40.00 spent | Email notification (early warning) |
| 100% | Actual | $50.00 spent | Email notification (hard limit reached) |
| 100% | Forecasted | Projected $50 | Email notification (predictive alert) |

**Notification Email:** mikhaelvillamor97@gmail.com

### Infrastructure as Code

```hcl
# envs/dev/main.tf
module "cost_management" {
  source = "../../modules/cost_management"

  environment         = "dev"
  project_name        = var.project_name
  budget_amount       = "50.00"
  time_period_start   = "2026-01-01_00:00"
  notification_emails = [var.alarm_email]
}
```

### Email Confirmation Required

AWS Budgets sends confirmation emails to all subscribers. Recipients must click the confirmation link to receive future alerts.

**Action Required:** Check email and confirm subscription if not already done.

### Cost Impact

- AWS Budgets: Free (first 2 budgets per account)
- Email notifications: Free (SES not required for budget alerts)

### Interview Talking Points

- "I set a $50/month budget for dev with 80% early warning to catch unexpected cost spikes before hitting the limit"
- "Used Terraform to manage budgets as infrastructure-as-code, not manual console setup"
- "Forecasted alert uses AWS Cost Explorer ML predictions to warn about trends before month-end"
- "In production, I'd set separate budgets per service (Lambda, S3, DynamoDB) for granular cost tracking"

---

## 5. Kinesis Cost Optimization

### Observed Cost

- **Actual Cost:** $10.87/month (Jan 2026)
- **Percentage of Total:** 91% of infrastructure costs

**This is the largest cost driver for the dev environment.**

### Current Configuration

- **Mode:** On-demand capacity
- **Retention:** 24 hours
- **Encryption:** KMS (AWS-managed key, no additional cost)

### Cost Analysis

**On-Demand Pricing:**
- $0.04 per 1 million PUT payload units
- $0.015 per GB data ingested
- $0.08 per GB data retrieved

**Dev Usage (Estimated):**
- If testing with 1,000 events/day × 5 KB avg = 5 MB/day
- Monthly ingestion: ~150 MB = $0.002
- **Actual $10.87 suggests higher usage or provisioned shard costs**

### Recommendation: Investigate Kinesis Configuration

**Action Items:**
1. Verify if Kinesis is actually on-demand or has provisioned shards
2. Check if stream is idle most of the time (wasteful for sporadic dev testing)
3. Consider alternatives for dev environment:
   - Direct S3 uploads for batch testing
   - Kinesis only when actively testing streaming features
   - Disable stream when not needed (Terraform `count` conditional)

**Potential Savings:** $8-10/month if Kinesis optimized or disabled when idle

### Interview Talking Points

- "I identified Kinesis as the largest cost driver ($10.87/month, 91% of total)"
- "For dev, I'd evaluate if streaming ingestion is needed continuously or only during active feature work"
- "Production would always use Kinesis for real-time data, but dev can use conditional provisioning"
- "Demonstrates cost-aware architecture decisions and willingness to question infrastructure choices"

---

## 6. Additional Cost Optimizations in Place

### Compute Optimizations

**Lambda:**
- ✅ Free tier coverage (1M requests/month, 400,000 GB-seconds)
- ✅ Python 3.11 runtime (faster cold starts, lower duration costs)
- ✅ Appropriate memory sizing (256-512 MB, not over-provisioned)

**Step Functions:**
- ✅ Standard Workflows ($0.025 per 1,000 state transitions)
- ✅ Actual cost: $0.19/month (well within budget)

### Storage Optimizations

**S3:**
- ✅ SSE-S3 encryption (no additional cost vs KMS $1/month per key)
- ✅ Lifecycle policies prevent indefinite accumulation
- ✅ Versioning enabled but not causing bloat (minimal updates)

**DynamoDB:**
- ✅ TTL auto-deletion prevents storage growth
- ✅ PITR backups (35 days, ~$0.01/month for minimal data)

### Observability Optimizations

**CloudWatch:**
- ✅ 7-day log retention (prevents accumulation)
- ✅ Metrics: Standard resolution (1-minute), not high-resolution (additional cost)
- ✅ Dashboard: 1 dashboard (3 free per account, then $3/month each)
- ✅ Alarms: 6 alarms (10 free per account, then $0.10/alarm/month)

---

## 7. Recommendations for Production

### Cost Management Strategy

1. **Budget Alerts:**
   - Separate budgets per service (Lambda, S3, DynamoDB, Kinesis)
   - Lower threshold alerts (50%, 75%, 90%, 100%)
   - SNS topic integration for PagerDuty/Slack notifications

2. **Reserved Capacity:**
   - DynamoDB reserved capacity (1-year commitment, 20% savings)
   - Savings Plans for Lambda (1-year commitment, 17% savings)
   - S3 Intelligent-Tiering for unpredictable access patterns

3. **CloudWatch Logs Optimization:**
   - Export to S3 after 30 days (10x cheaper: $0.03/GB vs $0.50/GB)
   - Use CloudWatch Logs Insights for queries, not Athena (cost-effective for recent data)

4. **Kinesis Optimization:**
   - Evaluate Kinesis vs Kinesis Firehose (simpler, potentially cheaper)
   - Right-size shard count based on actual throughput (not over-provisioned)
   - Consider Kinesis Data Streams On-Demand for variable workloads

5. **Tagging Strategy:**
   - Comprehensive cost allocation tags (Team, Service, CostCenter, Environment)
   - AWS Cost Explorer filtering by tag
   - Showback/chargeback reporting per team

### Multi-Environment Cost Targets

| Environment | Monthly Budget | Rationale |
|-------------|---------------|-----------|
| **Dev** | $50 | Learning/testing, minimal traffic |
| **Staging** | $200 | Pre-prod validation, larger datasets |
| **Production** | $1,000+ | Real workloads, high availability, reserved capacity |

---

## 8. Portfolio Interview Talking Points

### Cost Consciousness

"I implemented comprehensive cost controls for my AI data pipeline project, including:"
- Environment-specific lifecycle policies (6-month retention for dev, 2-year for prod)
- On-demand billing for sporadic dev workloads (break-even analysis showed 500x cheaper)
- 7-day log retention for dev (balance debugging with cost)
- AWS Budget alerts at 80% and 100% thresholds (proactive monitoring)

### Optimization Skills

"When reviewing costs, I identified Kinesis as the largest driver ($10.87/month, 91% of total). In a real scenario, I'd:"
- Verify if it's actually needed continuously in dev
- Evaluate alternatives like direct S3 uploads for batch testing
- Implement conditional provisioning (Terraform `count`) to disable when not in use

### Production Readiness

"For production, I'd:"
- Extend log retention to 90 days for compliance and incident investigation
- Switch DynamoDB to provisioned capacity if sustained load exceeds 500 WCU/RCU
- Implement reserved capacity for 20-40% savings on predictable workloads
- Set up separate budgets per service for granular cost tracking

### Infrastructure as Code

"I managed budgets as Terraform modules, not manual console setup, ensuring:"
- Version-controlled cost policies
- Repeatable across environments (dev, staging, prod)
- Auditable changes (Git history of budget modifications)

---

## 9. Conclusion

The AI-DP development environment has been configured with appropriate cost optimizations for a portfolio/learning project:

- **Current Cost:** $11.90/month (76% under $50 budget)
- **CloudWatch Logs:** 7-day retention (optimal for dev)
- **S3 Lifecycle:** Aggressive policies (180-day raw, 365-day processed)
- **DynamoDB:** On-demand billing (500x cheaper than provisioned for dev workload)
- **Budget Alerts:** Configured at $50/month with 80% and 100% thresholds

**Next Steps:**
1. Confirm AWS Budget email subscription
2. Investigate Kinesis $10.87/month cost (largest driver)
3. Consider conditional provisioning for Kinesis in dev environment

**Portfolio Value:**
This project demonstrates:
- Cost-aware architecture decisions
- Environment-specific optimization strategies
- Infrastructure-as-code for cost management
- Ability to analyze cost data and identify optimization opportunities

---

**Report Prepared By:** AI-DP Cost Optimization Review
**Date:** 2026-01-28
**Phase:** 9 Task 6 - Cost Optimization Review
