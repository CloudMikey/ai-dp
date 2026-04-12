#-------------------- Cost Management Module --------------------#
# AWS Budgets for monthly cost monitoring with configurable thresholds and email alerts.

locals {
  budget_name = "${var.project_name}-${var.environment}-monthly-budget"
}

#-------------------- AWS Budget --------------------#
resource "aws_budgets_budget" "monthly_cost" {
  name              = local.budget_name
  budget_type       = "COST"
  limit_amount      = var.budget_amount
  limit_unit        = "USD"
  time_period_start = var.time_period_start
  time_unit         = "MONTHLY"

  # Alert at 80% threshold
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_emails
  }

  # Alert at 100% threshold
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_emails
  }

  # Optional: Forecasted cost alert at 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.notification_emails
  }
}
