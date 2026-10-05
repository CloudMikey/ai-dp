# Observability Module

Creates a CloudWatch operational dashboard for the AI-DP pipeline.

## Dashboard Widgets

| Widget | Metrics |
|--------|---------|
| Lambda Invocations | ETL + Merge invocation counts |
| Lambda Errors | ETL + Merge error counts |
| Lambda Duration | ETL + Merge average duration |
| Kinesis Incoming Records | Records ingested per period |
| Kinesis Iterator Age | Consumer lag in milliseconds |
| Step Functions Executions | Started, Succeeded, Failed counts |
| DLQ Depth | Messages visible in the ETL DLQ |
| DynamoDB Capacity | Consumed read/write capacity units |

## Usage

```hcl
module "observability" {
  source = "../../modules/observability"

  environment  = "dev"
  project_name = var.project_name
  aws_region   = var.aws_region

  etl_lambda_function_name   = module.ingestion_stream.lambda_function_name
  merge_lambda_function_name = module.orchestration.lambda_function_name
  kinesis_stream_name        = module.ingestion_stream.kinesis_stream_name
  state_machine_name         = module.step_functions.state_machine_name
  state_machine_arn          = module.step_functions.state_machine_arn
  dynamodb_table_name        = module.hot_store.table_name
  etl_dlq_name               = module.ingestion_stream.dlq_name
}
```
