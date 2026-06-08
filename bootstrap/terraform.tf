terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bootstrap uses local backend - this state is kept locally
  # The S3 bucket created here will be used by all other environments
  backend "local" {
    path = "terraform.tfstate"
  }
}



