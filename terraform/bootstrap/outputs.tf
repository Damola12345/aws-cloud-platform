output "terraform_apply_role_arn_dev" {
  description = "Set as AWS_TERRAFORM_APPLY_ROLE_ARN_DEV in GitHub"
  value       = aws_iam_role.terraform_apply["dev"].arn
}

output "terraform_apply_role_arn_prod" {
  description = "Set as AWS_TERRAFORM_APPLY_ROLE_ARN_PROD in GitHub"
  value       = aws_iam_role.terraform_apply["prod"].arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "github_ci_role_arn" {
  description = "Set as AWS_CI_ROLE_ARN in GitHub - available immediately after bootstrap apply, before any environment exists"
  value       = aws_iam_role.github_ci.arn
}