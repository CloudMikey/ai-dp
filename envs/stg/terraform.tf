terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Backend configuration should be provided via backend config file or CLI
    # Example: terraform init -backend-config=backend-stg.hcl
    encrypt      = true
    use_lockfile = true # Native S3 locking (Terraform >= 1.11.0)
  }
}
