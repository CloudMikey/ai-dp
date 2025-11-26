#-------------------- Step Functions Orchestration Module --------------------#
# Minimal state machine with Pass state for EventBridge integration testing
# Phase 4: Validates end-to-end batch ingestion path (S3 → EventBridge → Step Functions)
# Phase 5+: Expand to parallel Lambda tasks for AI enrichment

locals {
  resource_prefix    = "${var.project_name}-${var.environment}"
  state_machine_name = "${local.resource_prefix}-orchestrator"
}

#-------------------- CloudWatch Log Group --------------------#
# Stores Step Functions execution logs for debugging
# Created before state machine to ensure logs are captured from first execution
# Retention: 7 days for dev (increase for prod to meet compliance requirements)

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${local.state_machine_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${local.state_machine_name}-logs"
      Description = "Step Functions execution logs"
    }
  )
}

#-------------------- Step Functions State Machine --------------------#
# Minimal Pass state for Phase 4 EventBridge integration testing
# Accepts S3 event from EventBridge, returns success message
# Future: Replace Pass state with Parallel tasks for AI enrichment (Phase 5+)

resource "aws_sfn_state_machine" "orchestrator" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions.arn

  # ASL definition: AI Enrichment workflow with AWS Comprehend
  # Phase 6: Parallel sentiment analysis and entity detection
  definition = jsonencode({
    Comment = "Phase 6: AI Enrichment - Comprehend sentiment and entity detection"
    StartAt = "PrepareComprehendInput"
    States = {
      # Extract S3 bucket and key from EventBridge event
      PrepareComprehendInput = {
        Type    = "Pass"
        Comment = "Extract S3 object details from EventBridge event"
        Parameters = {
          "bucket.$" = "$.detail.bucket.name"
          "key.$"    = "$.detail.object.key"
          "size.$"   = "$.detail.object.size"
        }
        Next = "ReadS3Object"
      }

      # Read S3 object content for Comprehend analysis
      # Uses AWS SDK integration for S3 GetObject
      ReadS3Object = {
        Type     = "Task"
        Comment  = "Read text content from S3 for AI analysis"
        Resource = "arn:aws:states:::aws-sdk:s3:getObject"
        Parameters = {
          "Bucket.$" = "$.bucket"
          "Key.$"    = "$.key"
        }
        ResultPath = "$.s3_response"
        Next       = "PrepareTextContent"
      }

      # Extract text content from S3 response and combine with metadata
      PrepareTextContent = {
        Type    = "Pass"
        Comment = "Combine S3 object content with metadata for AI analysis"
        Parameters = {
          "text_content.$" = "$.s3_response.Body"
          "bucket.$"       = "$.bucket"
          "key.$"          = "$.key"
          "size.$"         = "$.size"
        }
        Next = "ComprehendAnalysis"
      }

      # Parallel execution of Comprehend sentiment and entity detection
      ComprehendAnalysis = {
        Type    = "Parallel"
        Comment = "Run sentiment analysis and entity detection in parallel"
        Branches = [
          {
            StartAt = "DetectSentiment"
            States = {
              DetectSentiment = {
                Type     = "Task"
                Comment  = "Analyze text sentiment (positive, negative, neutral, mixed)"
                Resource = "arn:aws:states:::aws-sdk:comprehend:detectSentiment"
                Parameters = {
                  "LanguageCode" = "en"
                  "Text.$"       = "$.text_content"
                }
                End = true
              }
            }
          },
          {
            StartAt = "DetectEntities"
            States = {
              DetectEntities = {
                Type     = "Task"
                Comment  = "Extract named entities (people, places, organizations, etc.)"
                Resource = "arn:aws:states:::aws-sdk:comprehend:detectEntities"
                Parameters = {
                  "LanguageCode" = "en"
                  "Text.$"       = "$.text_content"
                }
                End = true
              }
            }
          }
        ]
        ResultPath = "$.comprehend_results"
        Next       = "FormatResults"
      }

      # Format results for merge Lambda (Phase 7)
      FormatResults = {
        Type    = "Pass"
        Comment = "Structure AI enrichment results for DynamoDB and S3 processed layer"
        Parameters = {
          "source_object" = {
            "bucket.$" = "$.bucket"
            "key.$"    = "$.key"
            "size.$"   = "$.size"
          }
          "ai_enrichment" = {
            "sentiment.$" = "$.comprehend_results[0]"
            "entities.$"  = "$.comprehend_results[1]"
          }
          "processing_metadata" = {
            "phase"          = "6-comprehend-complete"
            "timestamp.$"    = "$$.State.EnteredTime"
            "state_machine" = "ai-dp-dev-orchestrator"
          }
        }
        End = true
      }
    }
  })

  # CloudWatch Logs configuration - log level ALL for dev visibility
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = var.log_level
  }

  # Ensure dependencies are created first
  depends_on = [
    aws_cloudwatch_log_group.step_functions,
    aws_iam_role_policy.step_functions_logging
  ]

  tags = merge(
    var.tags,
    {
      Name        = local.state_machine_name
      Description = "Orchestrates batch data pipeline execution"
      Component   = "Orchestration"
    }
  )
}
