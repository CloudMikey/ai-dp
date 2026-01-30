#=============================================================================#
#                      Cost Management Module Outputs                         #
#=============================================================================#

output "budget_id" {
  description = "ID of the AWS Budget"
  value       = aws_budgets_budget.monthly_cost.id
}

output "budget_name" {
  description = "Name of the AWS Budget"
  value       = aws_budgets_budget.monthly_cost.name
}

output "budget_arn" {
  description = "ARN of the AWS Budget"
  value       = aws_budgets_budget.monthly_cost.arn
}
