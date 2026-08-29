
data "aws_iam_policy_document" "github_ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Any ref (branch/PR) in this exact repo - nothing else.
    # NOTE: matches GitHub's ID-suffixed subject format
    # (repo:ORG@ORG_ID/REPO@REPO_ID:*) - see the github_org_id/github_repo_id
    # variable comments in main.tf for why plain names alone don't match.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:*"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  name               = "${local.project}-gha-ci"
  assume_role_policy = data.aws_iam_policy_document.github_ci_trust.json
  tags               = { Purpose = "terraform-plan-ci" }
}

data "aws_iam_policy_document" "github_ci_permissions" {
  statement {
    sid    = "TerraformStateS3"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::finzla-terraform-state-dev",
      "arn:aws:s3:::finzla-terraform-state-dev/*",
      "arn:aws:s3:::finzla-terraform-state-prod",
      "arn:aws:s3:::finzla-terraform-state-prod/*",
    ]
  }


  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/finzla-terraform-locks-dev",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/finzla-terraform-locks-prod",
    ]
  }


  statement {
    sid    = "ReadOnlyPlan"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:GetRepositoryPolicy",
      "elasticloadbalancing:Describe*",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "logs:Describe*",
      "cloudwatch:Describe*",
      "cloudwatch:GetMetricData",
      "cloudwatch:ListMetrics",
      "sns:GetTopicAttributes",
      "application-autoscaling:Describe*",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
    ]
    resources = ["*"] # read-only describe/list/get calls only - no mutating verbs are granted anywhere in this policy
  }
}

resource "aws_iam_role_policy" "github_ci" {
  name   = "${local.project}-gha-ci-readonly"
  role   = aws_iam_role.github_ci.id
  policy = data.aws_iam_policy_document.github_ci_permissions.json
}