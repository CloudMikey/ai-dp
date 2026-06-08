output "state_machine_arn" {
  description = "ARN of the Step Functions state machine (for EventBridge targets and IAM policies)"
  value       = aws_sfn_state_machine.orchestrator.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.orchestrator.name
}

output "state_machine_id" {
  description = "ID of the Step Functions state machine"
  value       = aws_sfn_state_machine.orchestrator.id
}

output "execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for execution logs"
  value       = aws_cloudwatch_log_group.step_functions.name
}
