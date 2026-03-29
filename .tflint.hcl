config {
  # Module inspection type (default, local, all, none)
  call_module_type = "local"

  # Force provider version to be specified
  force = false
}

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS-specific rules
rule "aws_resource_missing_tags" {
  enabled = true
  tags = ["Environment", "Project", "ManagedBy"]
}

rule "aws_s3_bucket_versioning_enabled" {
  enabled = true
}


rule "aws_lambda_function_tracing_enabled" {
  enabled = true
}

rule "aws_cloudwatch_log_group_retention_in_days" {
  enabled = true
}

# Terraform best practices
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}
