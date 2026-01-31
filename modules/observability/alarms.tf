#-------------------- SNS Topic for Alarm Notifications --------------------#

resource "aws_sns_topic" "cloudwatch_alarms" {    # Broadcaster
  name = "${local.resource_prefix}-cloudwatch-alarms"

  tags = {
    Name        = "${local.resource_prefix}-cloudwatch-alarms"
    Description = "Notification topic for CloudWatch operational alarms"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" {     # Reciever
  for_each = toset(var.alarm_notification_emails)

  topic_arn = aws_sns_topic.cloudwatch_alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

#-------------------- Lambda Error Rate Alarms --------------------#
# Uses metric math to calculate error percentage: (errors / invocations) * 100

resource "aws_cloudwatch_metric_alarm" "etl_lambda_error_rate" {
  alarm_name          = "${local.resource_prefix}-etl-lambda-error-rate"
  alarm_description   = "ETL Lambda error rate exceeded ${var.lambda_error_rate_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.lambda_error_rate_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(invocations > 0, (errors / invocations) * 100, 0)"
    label       = "ETL Lambda Error Rate (%)"
    return_data = true
  }

  metric_query {        # pulls error count within 5
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = var.etl_lambda_function_name }
    }
  }

  metric_query {         # pulls invocation count within 5 min
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = var.etl_lambda_function_name }
    }
  }

  tags = {
    Name     = "${local.resource_prefix}-etl-lambda-error-rate"
    Severity = "High"
  }
}

resource "aws_cloudwatch_metric_alarm" "merge_lambda_error_rate" {
  alarm_name          = "${local.resource_prefix}-merge-lambda-error-rate"
  alarm_description   = "Merge Lambda error rate exceeded ${var.lambda_error_rate_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.lambda_error_rate_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(invocations > 0, (errors / invocations) * 100, 0)"
    label       = "Merge Lambda Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = var.merge_lambda_function_name }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = var.merge_lambda_function_name }
    }
  }

  tags = {
    Name     = "${local.resource_prefix}-merge-lambda-error-rate"
    Severity = "High"
  }
}

#-------------------- DLQ Depth Alarms --------------------#
# Immediate alert when any message appears in Dead Letter Queue

resource "aws_cloudwatch_metric_alarm" "etl_dlq_depth" {
  alarm_name          = "${local.resource_prefix}-etl-dlq-depth"
  alarm_description   = "ETL DLQ has messages - Lambda failures detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.dlq_depth_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {                 # Filters this specific SQS queue
    QueueName = var.etl_dlq_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name     = "${local.resource_prefix}-etl-dlq-depth"
    Severity = "Critical"
  }
}

resource "aws_cloudwatch_metric_alarm" "merge_dlq_depth" {
  alarm_name          = "${local.resource_prefix}-merge-dlq-depth"
  alarm_description   = "Merge DLQ has messages - Lambda failures detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.dlq_depth_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.merge_dlq_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name     = "${local.resource_prefix}-merge-dlq-depth"
    Severity = "Critical"
  }
}

#-------------------- Kinesis Iterator Age Alarm --------------------#
# High iterator age means Lambda is falling behind on stream processing

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${local.resource_prefix}-kinesis-iterator-age"
  alarm_description   = "Kinesis iterator age exceeded ${var.kinesis_iterator_age_threshold_ms / 1000}s - processing lag detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.kinesis_iterator_age_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = var.kinesis_stream_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name     = "${local.resource_prefix}-kinesis-iterator-age"
    Severity = "Medium"
  }
}

#-------------------- Step Functions Failure Alarm --------------------#
# Triggers when execution failures exceed threshold within evaluation period

resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  alarm_name          = "${local.resource_prefix}-step-functions-failures"
  alarm_description   = "Step Functions failures exceeded ${var.step_functions_failure_threshold} in 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = var.step_functions_failure_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name     = "${local.resource_prefix}-step-functions-failures"
    Severity = "High"
  }
}
