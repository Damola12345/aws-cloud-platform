data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# 1. ECS task execution role - used by the ECS agent itself to pull the image
#    from ECR and ship logs to CloudWatch. The application never assumes this
#    role; it's invisible to application code.
# =============================================================================

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# 2. ECS task role - assumed by the application itself at runtime (i.e. AWS
#    SDK calls made from inside the container, if any). This demo app makes
#    none, so the role is intentionally left with zero custom permissions -
#    a placeholder for future least-privilege grants (e.g. a specific SSM
#    parameter or Secrets Manager secret) rather than a broad default.
# =============================================================================

resource "aws_iam_role" "ecs_task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
  tags               = var.tags
}

# =============================================================================
# 3. GitHub OIDC federation - lets GitHub Actions assume AWS roles with a
#    short-lived token instead of long-lived access keys stored as secrets.
#    The provider itself, AND the read-only `github_ci` plan role, are both
#    created ONCE in terraform/bootstrap - not here. Why: github_ci is needed
#    to pass the PR check on the very first PR, but this environment's own
#    Terraform (which is what would otherwise create it) doesn't exist until
#    AFTER that PR merges. Creating it in bootstrap instead breaks that
#    circular dependency - see terraform/bootstrap/iam-ci.tf.
#    The OIDC provider ARN is fully deterministic from the account ID, so
#    it's referenced here as a plain string - no cross-state data source
#    needed.
# =============================================================================

locals {
  oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}


# -----------------------------------------------------------------------------
# 3b. Deploy role - assumable ONLY when the workflow job declares
#     `environment: <var.environment>` in GitHub Actions. GitHub Environments
#     can require manual reviewer approval before the job is allowed to run,
#     which is what gates production deployments (see README "who can deploy").
#     Scoped tightly: push to one ECR repo, update one ECS service, and
#     PassRole only the two task roles this app actually uses.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "github_deploy_trust" {
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
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "github_deploy_permissions" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this specific action does not support resource-level scoping
  }

  statement {
    sid    = "ECRPushToThisRepoOnly"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid    = "RegisterTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    # RegisterTaskDefinition does not support resource-level restriction to a
    # family in the policy resource element; family scoping is enforced by
    # the ECS service only ever being updated with this app's family (below).
    resources = ["*"]
  }

  statement {
    sid    = "UpdateThisServiceOnly"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
    ]
    resources = [var.ecs_service_arn, var.ecs_cluster_arn]
  }

  statement {
    sid     = "PassRoleToECSTasksOnly"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-ecs-task-execution",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-ecs-task",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid    = "ReadDeployHealthSignals"
    effect = "Allow"
    actions = [
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${var.log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.name}-gha-deploy-scoped"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_permissions.json
}
