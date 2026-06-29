locals {
  resource_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_cloudwatch_dashboard" "operations" {
  dashboard_name = "${local.resource_prefix}-operations"

  dashboard_body = jsonencode({
    widgets = [

      # Row 1: Lambda invocation counts
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = var.aws_region
          period = 300 # 5 min
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.etl_lambda_function_name, { label = "ETL Lambda" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.merge_lambda_function_name, { label = "Merge Lambda" }]
          ]
        }
      },

      # Row 2 left: Lambda error counts
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.etl_lambda_function_name, { label = "ETL Errors", color = "#d62728" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.merge_lambda_function_name, { label = "Merge Errors", color = "#ff7f0e" }]
          ]
        }
      },

      # Row 2 right: Lambda execution duration
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Duration (avg ms)"
          region = var.aws_region
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.etl_lambda_function_name, { label = "ETL Duration" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.merge_lambda_function_name, { label = "Merge Duration" }]
          ]
        }
      },

      # Row 3: Kinesis throughput and consumer lag
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Kinesis - Incoming Records"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", "StreamName", var.kinesis_stream_name, { label = "Incoming Records" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Kinesis - Iterator Age (ms)" # How long data is in Kinesis 
          region = var.aws_region
          period = 300
          stat   = "Maximum"
          metrics = [
            ["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.kinesis_stream_name, { label = "Iterator Age", color = "#d62728" }]
          ]
        }
      },

      # Row 4: Step Functions execution outcomes
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "Step Functions Executions"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.state_machine_arn, { label = "Started" }],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.state_machine_arn, { label = "Succeeded", color = "#2ca02c" }],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.state_machine_arn, { label = "Failed", color = "#d62728" }]
          ]
        }
      },

      # Row 5: Dead-letter queue backlog
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 24
        height = 6
        properties = {
          title  = "Dead Letter Queue Messages"
          region = var.aws_region
          period = 300
          stat   = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.etl_dlq_name, { label = "ETL DLQ", color = "#d62728" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.merge_dlq_name, { label = "Merge DLQ", color = "#ff7f0e" }]
          ]
        }
      },

      # Row 6: DynamoDB consumed capacity
      {
        type   = "metric"
        x      = 0
        y      = 30
        width  = 24
        height = 6
        properties = {
          title  = "DynamoDB Consumed Capacity"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name, { label = "Read Capacity" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_table_name, { label = "Write Capacity", color = "#ff7f0e" }]
          ]
        }
      }
    ]
  })
}
