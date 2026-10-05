output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "backend_config" {
  description = "Backend configuration to use in environment backend.tf files"
  value = {
    bucket       = aws_s3_bucket.terraform_state.id
    region       = aws_s3_bucket.terraform_state.region
    encrypt      = true
    use_lockfile = true
  }
}




