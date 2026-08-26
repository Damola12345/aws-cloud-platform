data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
}

data "aws_iam_policy_document" "terraform_apply_trust" {
  for_each = toset(local.environments)

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
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:infra-${each.value}"]
    }
  }
}

resource "aws_iam_role" "terraform_apply" {
  for_each = toset(local.environments)

  name               = "${local.project}-${each.value}-gha-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.terraform_apply_trust[each.value].json
  tags               = { Purpose = "terraform-apply-ci", Environment = each.value }
}

data "aws_iam_policy_document" "terraform_apply_permissions" {
  for_each = toset(local.environments)

  # --- Terraform's own remote state for this one environment -------------
  statement {
    sid    = "StateReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::finzla-terraform-state-${each.value}",
      "arn:aws:s3:::finzla-terraform-state-${each.value}/*",
    ]
  }
  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/finzla-terraform-locks-${each.value}"]
  }

  statement {
    sid    = "Networking"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # --- ECR - scoped to this project's repos only --------------------------
  statement {
    sid       = "ECR"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/finzla-*"]
  }
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken", "ecr:DescribeRegistry"]
    resources = ["*"]
  }

  # --- ECS - cluster/service/task-def actions can't all be resource-scoped
  statement {
    sid       = "ECS"
    effect    = "Allow"
    actions   = ["ecs:*"]
    resources = ["*"]
  }

  # --- Load balancing -------------------------------------------------------
  statement {
    sid       = "ELB"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:*"]
    resources = ["*"]
  }

  # --- Application Auto Scaling for the ECS service -----------------------
  statement {
    sid       = "AppAutoScaling"
    effect    = "Allow"
    actions   = ["application-autoscaling:*"]
    resources = ["*"]
  }

  # --- Logs, CloudWatch alarms, SNS - scoped to this project's naming -----
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/finzla-*"]
  }
  statement {
    sid       = "CloudWatchAlarms"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource"]
    resources = ["arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:finzla-*"]
  }
  statement {
    sid       = "SNS"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = ["arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:finzla-*"]
  }


  statement {
    sid       = "Route53"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName", "route53:GetHostedZone", "route53:ChangeResourceRecordSets", "route53:GetChange", "route53:ListResourceRecordSets"]
    resources = ["*"]
  }

  # --- ACM - read-only, just to look up the certificate ARN ---------------
  statement {
    sid       = "ACMReadOnly"
    effect    = "Allow"
    actions   = ["acm:DescribeCertificate", "acm:ListCertificates", "acm:GetCertificate"]
    resources = ["*"]
  }

  # --- IAM - the sensitive part. Scoped strictly to this project's naming
  # prefix, so it cannot create, modify, or delete any IAM role/policy that
  # doesn't belong to this project - including anything belonging to a
  # different application in the same account.
  statement {
    sid    = "IAMScopedToProject"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/finzla-*"]
  }
  statement {
    sid       = "IAMPassRoleScoped"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/finzla-*"]
  }
  statement {
    sid       = "IAMOIDCProviderReadOnly"
    effect    = "Allow"
    actions   = ["iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  # --- STS, needed for the account-id/region data sources every module uses
  statement {
    sid       = "STS"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_apply" {
  for_each = toset(local.environments)

  name   = "${local.project}-${each.value}-gha-terraform-apply-scoped"
  role   = aws_iam_role.terraform_apply[each.value].id
  policy = data.aws_iam_policy_document.terraform_apply_permissions[each.value].json
}
