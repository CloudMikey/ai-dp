resource "aws_iam_role" "glue_crawler" {
  name        = "${var.project_name}-${var.environment}-glue-crawler-role"
  description = "IAM role for Glue Crawler to access S3 and Glue Data Catalog"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "${var.project_name}-${var.environment}-glue-crawler-role"
      Component = "Analytics"
      Purpose   = "GlueCrawlerExecution"
    }
  )
}

# Scoped to processed/* prefix only

resource "aws_iam_role_policy" "glue_s3_read" {
  name = "s3-read-access"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "${var.data_lake_bucket_arn}/processed/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          var.data_lake_bucket_arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = ["processed/*"]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_catalog_access" {
  name = "glue-catalog-access"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition",
          "glue:BatchUpdatePartition",
          "glue:BatchGetPartition",
          "glue:CreateDatabase",
          "glue:UpdateDatabase",
          "glue:GetDatabase",
          "glue:GetDatabases"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:*:catalog",
          "arn:aws:glue:${var.aws_region}:*:database/${var.project_name}-${var.environment}-analytics",
          "arn:aws:glue:${var.aws_region}:*:table/${var.project_name}-${var.environment}-analytics/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_logs" {
  name = "cloudwatch-logs-access"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws-glue/crawlers:*"
        ]
      }
    ]
  })
}
