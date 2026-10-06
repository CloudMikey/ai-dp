# IAM role assumed by GitHub Actions via OIDC for Terraform CI/CD (no long-term credentials)
#
# The OIDC Identity Provider already exists in this account (created for a
# previous project), so it is looked up rather than created. In an account
# without one, set enable_github_oidc = false to deploy the pipeline alone.

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions_dev" {
  count       = var.enable_github_oidc ? 1 : 0
  name        = "ai-dp-dev-github-actions"
  description = "GitHub Actions OIDC role for AI-DP dev Terraform deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github_actions[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Any branch, tag, or PR in this repo can assume the role, so a protected
          # main branch (Settings -> Branches) is what keeps unreviewed code from deploying
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

# Adding count changed the address; this keeps the existing role instead of replacing it
moved {
  from = aws_iam_role.github_actions_dev
  to   = aws_iam_role.github_actions_dev[0]
}

# Note: The inline policy (ai-dp-dev-terraform-policy) is managed via the AWS Console.
# The role itself is in Terraform state; the policy is discovered at deploy time.
