output "dashboard_name" {
  description = "Name of the CloudWatch operational dashboard"
  value       = aws_cloudwatch_dashboard.operations.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch operational dashboard"
  value       = aws_cloudwatch_dashboard.operations.dashboard_arn
}

output "sns_topic_arn" {
  description = "ARN of SNS topic for CloudWatch alarm notifications"
  value       = aws_sns_topic.cloudwatch_alarms.arn
}

output "sns_topic_name" {
  description = "Name of SNS topic for CloudWatch alarm notifications"
  value       = aws_sns_topic.cloudwatch_alarms.name
}

output "alarm_names" {
  description = "List of all CloudWatch alarm names"
  value = [
    aws_cloudwatch_metric_alarm.etl_lambda_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.merge_lambda_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.etl_dlq_depth.alarm_name,
    aws_cloudwatch_metric_alarm.merge_dlq_depth.alarm_name,
    aws_cloudwatch_metric_alarm.kinesis_iterator_age.alarm_name,
    aws_cloudwatch_metric_alarm.step_functions_failures.alarm_name
  ]
}
