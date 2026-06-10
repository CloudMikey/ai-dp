# IAM role assumed by GitHub Actions via OIDC for Terraform CI/CD (no long-term credentials)
#
# The OIDC Identity Provider already exists in this account (created for a
# previous project). We reference it via data source rather than recreating it.
# Provider: token.actions.githubusercontent.com
#
# After creating the role in the AWS Console (per docs/phase10-task1-guide.md),
# import it into state with:
#   terraform -chdir=envs/dev import aws_iam_role.github_actions_dev ai-dp-dev-github-actions

data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions_dev" {
  name        = "ai-dp-dev-github-actions"
  description = "GitHub Actions OIDC role for AI-DP dev Terraform deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Trusts any workflow triggered from the AI-DP repo
          # Branch/environment restrictions enforced via GitHub branch protection rules (Task 4)
          "token.actions.githubusercontent.com:sub" = "repo:CloudMikey/ai-dp:*"
        }
      }
    }]
  })

  tags = {
    Name        = "ai-dp-dev-github-actions"
    Description = "GitHub Actions OIDC role for AI-DP dev deployments"
  }
}

# Note: The inline policy (ai-dp-dev-terraform-policy) is managed via the AWS Console.
# The role itself is in Terraform state; the policy is discovered at deploy time.



