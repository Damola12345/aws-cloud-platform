# ---------------------------------------------------------------------------
# github_ci: the read-only role pr-validation.yml uses for `terraform fmt/
# validate/plan` on every PR. Lives HERE rather than in modules/iam (used by
# environments/dev and environments/prod) for a specific reason:
#
# environments/dev's own Terraform is what would otherwise create this role
# - but that Terraform only ever gets applied by infra.yml's apply-dev job,
# which only runs on a PUSH TO MASTER, i.e. AFTER a PR has already merged.
# pr-validation.yml needs this role to pass its check BEFORE merge. That's a
# circular dependency: the role needed to pass the PR check doesn't exist
# until the PR that check is gating has already merged.
#
# Creating it here instead - in the one-time, human-applied bootstrap layer -
# means it exists from the very first PR onward, no chicken-and-egg. It's
# also genuinely a single, shared, account-wide role rather than a
# per-environment one: it's entirely read-only, its policy already used
# wildcard resources rather than per-environment ARNs, and pr-validation.yml
# only ever needs one of it regardless of how many environments exist.
# ---------------------------------------------------------------------------

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

# tfsec attributes the wildcard-action finding below to this WHOLE data
# block (not the individual "ReadOnlyPlan" statement inside it), so the
# ignore has to sit here, directly above the block tfsec actually reports
# against - not above the nested statement, which tfsec's ignore-matching
# doesn't recognize. Scoped correctly regardless: ignores only suppress
# THIS check ID for this block, so the S3/DynamoDB statements above (which
# don't use wildcards) are unaffected either way.
#
# Justification for the wildcard actions in "ReadOnlyPlan" specifically:
# every action there is a read-only Describe/List/Get verb (this whole role
# can never create, modify, or delete anything - see the module-level
# header comment), and AWS's IAM model doesn't support resource-level
# scoping for most of these read APIs regardless. The wildcard is on the
# ACTION SUFFIX (e.g. "Describe*") and the resource, not on write
# permissions, which is the actual risk this check exists to catch.
#tfsec:ignore:aws-iam-no-policy-wildcards
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

  # Named "Lock", not "ReadOnly": PutItem/DeleteItem/UpdateItem here are for
  # acquiring and releasing the state LOCK only, not for writing state
  # content - `terraform plan` (and even `init`) still needs to lock the
  # state file to safely read it, even though this role can never write
  # state content itself (see TerraformStateS3 above: GetObject/ListBucket
  # only, no PutObject/DeleteObject anywhere in this policy). UpdateItem is
  # included defensively even though classic S3+DynamoDB locking normally
  # only needs Put/Delete - cheap to grant, scoped only to these two lock
  # tables, and avoids a possible future Terraform-version edge case using
  # it instead.
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

  # tfsec flags every wildcarded action below (aws-iam-no-policy-wildcards) -
  # justification moved to the ignore annotation above the outer data block
  # (see top of this file's github_ci_permissions block) - tfsec's ignore
  # matching only recognizes a comment directly above the block it actually
  # reports the finding against, which for this check is the whole `data`
  # source, not this nested statement.
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