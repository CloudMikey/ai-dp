# Batch processing workflow: S3 raw/ → EventBridge → Step Functions → Comprehend → Merge Lambda

locals {
  resource_prefix    = "${var.project_name}-${var.environment}"
  state_machine_name = "${local.resource_prefix}-orchestrator"

  # Retry transient SDK failures (throttling, 5xx); fail fast on errors a retry can't fix.
  # Retriers match in order, so the MaxAttempts = 0 entry must come first.
  sdk_task_retry = [
    {
      ErrorEquals = [
        "Comprehend.TextSizeLimitExceededException",
        "Comprehend.InvalidRequestException",
        "Comprehend.UnsupportedLanguageException",
        "S3.NoSuchKeyException",
        "S3.InvalidObjectStateException"
      ]
      MaxAttempts = 0
    },
    {
      ErrorEquals     = ["States.TaskFailed"]
      IntervalSeconds = 2
      MaxAttempts     = 3
      BackoffRate     = 2.0
      JitterStrategy  = "FULL"
    }
  ]
}

# Logs execution history for debugging state machine failures and API errors
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

resource "aws_sfn_state_machine" "orchestrator" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "AI Enrichment: reads S3 objects, extracts the text to score, runs Comprehend (sentiment + entities in parallel), merges results"
    StartAt = "PrepareComprehendInput"
    States = {
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

      ReadS3Object = {
        Type     = "Task"
        Comment  = "Read text content from S3 for AI analysis"
        Resource = "arn:aws:states:::aws-sdk:s3:getObject"
        Parameters = {
          "Bucket.$" = "$.bucket"
          "Key.$"    = "$.key"
        }
        ResultPath = "$.s3_response"
        Retry      = local.sdk_task_retry
        Next       = "CheckFileFormat"
      }

      # Streaming events arrive as JSON envelopes (event_type, timestamps, text);
      # only the review text should be scored, not the metadata around it.
      CheckFileFormat = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.key"
            StringMatches = "*.json"
            Next          = "ParseJsonEvent"
          }
        ]
        Default = "PrepareTextContent"
      }

      ParseJsonEvent = {
        Type = "Pass"
        Parameters = {
          "event.$"  = "States.StringToJson($.s3_response.Body)"
          "bucket.$" = "$.bucket"
          "key.$"    = "$.key"
          "size.$"   = "$.size"
        }
        Next = "CheckForText"
      }

      CheckForText = {
        Type = "Choice"
        Choices = [
          {
            # IsPresent first: comparing a missing path is a runtime error, not a false
            And = [
              { Variable = "$.event.text", IsPresent = true },
              { Variable = "$.event.text", IsString = true }
            ]
            Next = "ExtractEventText"
          }
        ]
        Default = "NoTextToAnalyze"
      }

      # Events without a text field (e.g. load-test pings) have nothing to score
      NoTextToAnalyze = {
        Type = "Succeed"
      }

      ExtractEventText = {
        Type = "Pass"
        Parameters = {
          "text_content.$" = "$.event.text"
          "bucket.$"       = "$.bucket"
          "key.$"          = "$.key"
          "size.$"         = "$.size"
        }
        Next = "ComprehendAnalysis"
      }

      # Batch uploads are plain text: the whole body is the document
      PrepareTextContent = {
        Type = "Pass"
        Parameters = {
          "text_content.$" = "$.s3_response.Body"
          "bucket.$"       = "$.bucket"
          "key.$"          = "$.key"
          "size.$"         = "$.size"
        }
        Next = "ComprehendAnalysis"
      }

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
                Retry = local.sdk_task_retry
                End   = true
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
                Retry = local.sdk_task_retry
                End   = true
              }
            }
          }
        ]
        ResultPath = "$.comprehend_results"
        Next       = "FormatResults"
      }

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
            "timestamp.$"     = "$$.State.EnteredTime"
            "state_machine.$" = "$$.StateMachine.Name"
          }
        }
        Next = "InvokeMergeLambda"
      }

      InvokeMergeLambda = {
        Type     = "Task"
        Comment  = "Merge AI enrichment results and write to S3 processed layer + DynamoDB hot store"
        Resource = var.merge_lambda_arn
        Parameters = {
          "source_object.$"       = "$.source_object"
          "ai_enrichment.$"       = "$.ai_enrichment"
          "processing_metadata.$" = "$.processing_metadata"
        }
        ResultPath = "$.merge_result"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "MergeFailed"
          }
        ]
        Next = "MergeComplete"
      }

      MergeComplete = {
        Type    = "Succeed"
        Comment = "Pipeline complete - enriched data written to S3 processed layer and DynamoDB"
      }

      MergeFailed = {
        Type    = "Fail"
        Comment = "Merge Lambda failed - error and cause are in this execution's history and the merge Lambda logs"
        Error   = "MergeLambdaError"
        Cause   = "Lambda invocation failed after retries"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = var.log_level
  }

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
