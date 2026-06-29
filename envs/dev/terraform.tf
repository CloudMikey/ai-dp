terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    # The rest of the config is in the .hcl file
    encrypt      = true
    use_lockfile = true # Native S3 locking (Terraform >= 1.11.0)
  }
}



