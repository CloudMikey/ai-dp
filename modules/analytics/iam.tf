#-------------------- Glue Crawler IAM Role --------------------#

resource "aws_iam_role" "glue_crawler" {
  name               = "${var.project_name}-${var.environment}-glue-crawler-role"
  description        = "IAM role for Glue Crawler to access S3 and Glue Data Catalog"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = merge(
    var.tags,
    {
      Name      = "${var.project_name}-${var.environment}-glue-crawler-role"
      Component = "Analytics"
      Purpose   = "GlueCrawlerExecution"
    }
  )
}

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#-------------------- S3 Read Permissions --------------------#
# Scoped to processed/* prefix only

resource "aws_iam_role_policy" "glue_s3_read" {
  name   = "s3-read-access"
  role   = aws_iam_role.glue_crawler.id
  policy = data.aws_iam_policy_document.glue_s3_read.json
}

data "aws_iam_policy_document" "glue_s3_read" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = [
      "${var.data_lake_bucket_arn}/processed/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      var.data_lake_bucket_arn
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["processed/*"]
    }
  }
}

#-------------------- Glue Data Catalog Permissions --------------------#

resource "aws_iam_role_policy" "glue_catalog_access" {
  name   = "glue-catalog-access"
  role   = aws_iam_role.glue_crawler.id
  policy = data.aws_iam_policy_document.glue_catalog_access.json
}

data "aws_iam_policy_document" "glue_catalog_access" {
  statement {
    effect = "Allow"

    actions = [
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

    resources = [
      "arn:aws:glue:${var.aws_region}:*:catalog",
      "arn:aws:glue:${var.aws_region}:*:database/${var.project_name}-${var.environment}-analytics",
      "arn:aws:glue:${var.aws_region}:*:table/${var.project_name}-${var.environment}-analytics/*"
    ]
  }
}

#-------------------- CloudWatch Logs Permissions --------------------#

resource "aws_iam_role_policy" "glue_logs" {
  name   = "cloudwatch-logs-access"
  role   = aws_iam_role.glue_crawler.id
  policy = data.aws_iam_policy_document.glue_logs.json
}

data "aws_iam_policy_document" "glue_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws-glue/crawlers:*"
    ]
  }
}
