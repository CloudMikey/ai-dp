#-------------------- DynamoDB Hot Store --------------------#
# Fast queries for recent AI-enriched data (auto-deletes old records via TTL)

locals {
  table_name = "${var.project_name}-${var.environment}-enriched-data"
}

resource "aws_dynamodb_table" "enriched_data" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "recordId"
  range_key    = "timestamp"
  attribute {
    name = "recordId"
    type = "S"
  }
 
  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "recordType"
    type = "S"
  }

  # GSI for time-based queries by recordType
  global_secondary_index {
    name            = "timestamp-index"
    hash_key        = "recordType"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = var.enable_ttl
  }

  tags = {
    Name        = local.table_name
    Description = "Hot store for AI-enriched data - recent records only"
  }
}
