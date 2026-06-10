# AI Enrichment Module

## Overview

This module provides IAM permissions for Step Functions to integrate with AWS Comprehend for AI-powered text analysis. AWS Comprehend is a serverless natural language processing (NLP) service, so no infrastructure resources need to be provisioned—only IAM policies.

## Portfolio Notes

**Interview Talking Points:**
- **Serverless AI Integration**: Demonstrates understanding of AWS managed AI services
- **Service Orchestration**: Shows Step Functions coordinating multiple AI tasks
- **IAM Best Practices**: Least-privilege permissions scoped to specific Comprehend actions
- **Cost Optimization**: Comprehend is pay-per-request with no minimum fees

## Features

- **Sentiment Analysis**: `comprehend:DetectSentiment` - analyzes positive/negative/neutral sentiment
- **Entity Detection**: `comprehend:DetectEntities` - extracts people, places, organizations, dates, etc.
- **IAM Policy**: Creates reusable policy that can be attached to Step Functions execution role

## Architecture

```
Step Functions State Machine
    ↓
AWS Comprehend (Serverless)
    ├── DetectSentiment API
    └── DetectEntities API
```

## Usage

```hcl
module "ai_enrichment" {
  source = "../../modules/ai_enrichment"

  environment  = "dev"
  project_name = "ai-dp"
}

# Attach policy to Step Functions role
resource "aws_iam_role_policy_attachment" "comprehend" {
  role       = aws_iam_role.step_functions.name
  policy_arn = module.ai_enrichment.comprehend_policy_arn
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| environment | Environment name (dev, stg, prod) | string | yes |
| project_name | Project name for resource naming | string | yes |

## Outputs

| Name | Description |
|------|-------------|
| comprehend_policy_arn | ARN of IAM policy for Comprehend access |
| comprehend_policy_name | Name of the Comprehend IAM policy |

## AWS Comprehend Pricing

- **Pay-per-request model**: $0.0001 per character (100 characters minimum)
- **No minimum fees or upfront costs**
- **Example**: Analyzing 1MB of text (~1M characters) = ~$0.10

## IAM Permissions

The module creates an IAM policy with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "comprehend:DetectSentiment",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "comprehend:DetectEntities",
      "Resource": "*"
    }
  ]
}
```

**Note**: Comprehend APIs don't support resource-level permissions, so `"Resource": "*"` is required.

## Step Functions Integration Pattern

This module enables Step Functions to call Comprehend using the AWS SDK integration pattern:

```json
{
  "Type": "Task",
  "Resource": "arn:aws:states:::aws-sdk:comprehend:detectSentiment",
  "Parameters": {
    "LanguageCode": "en",
    "Text.$": "$.text_content"
  },
  "ResultPath": "$.sentiment",
  "Next": "DetectEntities"
}
```

## Future Enhancements (Optional)

- **Amazon Rekognition**: Image analysis (labels, faces, text extraction)
- **Amazon SageMaker**: Custom ML models for anomaly detection
- **Amazon Translate**: Multi-language support
- **Amazon Textract**: Document analysis and OCR

**Portfolio Decision**: Start with Comprehend only (simplest, lowest cost). Add SageMaker later if needed to demonstrate custom ML integration.

## Resources Created

- `aws_iam_policy.comprehend` - IAM policy for Comprehend permissions

## Dependencies

None - this is a foundational module that provides IAM policies for other modules to use.

## Testing

Test Comprehend integration from Step Functions:

```bash
# Upload text file to S3 raw/
aws s3 cp sample.txt s3://ai-dp-data-lake-dev-us-west-2/raw/sample.txt

# EventBridge triggers Step Functions
# Step Functions calls Comprehend DetectSentiment & DetectEntities

# Check execution results
aws stepfunctions list-executions --state-machine-arn <state-machine-arn>
aws stepfunctions describe-execution --execution-arn <execution-arn>
```

## Compliance & Security

- **Data Privacy**: Comprehend does not store analyzed text
- **Encryption**: All API calls use TLS 1.2+
- **Least Privilege**: Policy only grants required Comprehend actions
- **Audit Trail**: CloudWatch Logs capture all API calls

## Related Documentation

- [AWS Comprehend Developer Guide](https://docs.aws.amazon.com/comprehend/latest/dg/what-is.html)
- [Step Functions Service Integrations](https://docs.aws.amazon.com/step-functions/latest/dg/supported-services-awssdk.html)
- [Comprehend API Reference](https://docs.aws.amazon.com/comprehend/latest/APIReference/Welcome.html)
