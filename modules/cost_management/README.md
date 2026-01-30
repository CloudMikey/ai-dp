# Cost Management Module

This module manages AWS Budgets for cost monitoring and alerting across environments.

## Features

- Monthly budget tracking with configurable dollar amounts
- Multi-threshold alerts (80%, 100% actual + 100% forecasted)
- Email notifications for cost overruns
- Optional cost filtering by project tags
- Environment-specific budget configurations

## Usage

```hcl
module "cost_management" {
  source = "../../modules/cost_management"

  project_name  = "ai-dp"
  environment   = "dev"
  budget_amount = "50.00"

  notification_emails = [
    "your-email@example.com"
  ]

  tags = {
    Component = "CostManagement"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Name of the project | string | - | yes |
| environment | Environment name (dev, stg, prod) | string | - | yes |
| budget_amount | Monthly budget amount in USD | string | "50.00" | no |
| time_period_start | Start date for budget tracking (YYYY-MM-DD_HH:MM) | string | "2026-01-01_00:00" | no |
| notification_emails | List of email addresses for budget alerts | list(string) | - | yes |
| tags | Additional tags for resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| budget_id | ID of the AWS Budget |
| budget_name | Name of the AWS Budget |
| budget_arn | ARN of the AWS Budget |

## Alert Thresholds

The module configures three alert thresholds:

1. **80% Actual Cost**: Early warning when spending reaches 80% of budget
2. **100% Actual Cost**: Alert when budget limit is reached
3. **100% Forecasted Cost**: Predictive alert based on spending trends

## Cost Filtering

The budget automatically filters costs by the project tag to ensure only relevant infrastructure costs are tracked:

```hcl
cost_filter {
  name   = "TagKeyValue"
  values = ["user:Project$${var.project_name}"]
}
```

## Email Subscriptions

When the budget is first created, AWS will send confirmation emails to all addresses in `notification_emails`. Recipients must click the confirmation link to receive future alerts.

## Environment-Specific Examples

### Development
```hcl
budget_amount = "50.00"  # Lower limit for dev/test
```

### Staging
```hcl
budget_amount = "200.00"  # Moderate limit for staging
```

### Production
```hcl
budget_amount = "1000.00"  # Higher limit for production workloads
```

## Interview Talking Points

- Demonstrates proactive cost management through infrastructure-as-code
- Shows understanding of environment-appropriate budget thresholds
- Implements multi-threshold alerting (early warning + hard limit)
- Uses AWS native tools (Budgets) rather than third-party solutions
- Configurable and reusable across multiple environments
