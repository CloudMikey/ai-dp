#-------------------- DynamoDB Hot Store Table --------------------#
# Stores AI-enriched data for fast queries (hot data)
# Data older than TTL period gets auto-deleted (archives remain in S3)

locals {
  table_name = "${var.project_name}-${var.environment}-enriched-data"
}

resource "aws_dynamodb_table" "enriched_data" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand: no capacity planning needed
  hash_key     = "recordId"        # Partition key
  range_key    = "timestamp"       # Sort key for time queries

  # Only define attributes used in keys (not all attributes)
  attribute {
    name = "recordId"
    type = "S" # String
  }
 
  attribute {
    name = "timestamp"
    type = "N" # Number (Unix epoch milliseconds)
  }

  attribute {
    name = "recordType"
    type = "S" # String (for GSI partition key)
  }

  #-------------------- Global Secondary Index --------------------#
  # Enables time-based queries: "Get all records of type X from date range Y"

  global_secondary_index {
    name            = "timestamp-index"
    hash_key        = "recordType"
    range_key       = "timestamp"
    projection_type = "ALL" # Include all attributes (simpler for portfolio)
  }

  #-------------------- Point-in-Time Recovery --------------------#
  # Allows restore to any point in last 35 days (disaster recovery)

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  #-------------------- Time To Live (TTL) --------------------#
  # Auto-deletes records after expiration (cost optimization)

  ttl {
    attribute_name = "expiresAt" # Merge Lambda sets this to currentTime + 30 days
    enabled        = var.enable_ttl
  }

  # Tags applied via provider default_tags (see envs/dev/main.tf)
  # Only add resource-specific tags here
  tags = {
    Name        = local.table_name
    Description = "Hot store for AI-enriched data - recent records only"
  }
}
