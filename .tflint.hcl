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
# Disabled: project uses provider default_tags + merge(var.tags, {...}) pattern
# tflint cannot statically verify tags passed through variables or merge()
rule "aws_resource_missing_tags" {
  enabled = false
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
