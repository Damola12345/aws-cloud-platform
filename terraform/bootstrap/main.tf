# ---------------------------------------------------------------------------
# One-time bootstrap: creates the S3 buckets + DynamoDB tables that the
# dev/ and prod/ environments use as their remote state backend, PLUS the
# GitHub OIDC provider and the "terraform_apply" IAM roles that let GitHub
# Actions actually create/update/destroy the rest of the infrastructure.
#
# Why these live here and not in environments/dev or environments/prod: a
# GitHub Actions workflow can't be the thing that creates the very first
# piece of AWS infrastructure, because it needs an IAM role to assume - and
# that role IS infrastructure. Everything in this file is the permanent,
# human-managed foundation that survives a `terraform destroy` of dev/prod;
# everything else (VPC, ALB, ECS, IAM app-roles, DNS, monitoring) is fully
# destroyable and re-creatable by CI once this exists.
#
# This config itself uses LOCAL state (chicken-and-egg problem: you can't
# store state for the thing that stores your state). Run it once per
# account, by a human with elevated (but still not AdministratorAccess)
# permissions, and then re-run `terraform apply` here only when you
# deliberately want to change this foundation layer itself (e.g. rotating
# the trusted repo) - it is intentionally kept out of the CI pipeline.
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#
# Separate buckets/tables per environment (rather than one shared bucket
# with different keys) mean a mistake in dev tooling/permissions can never
# touch prod state.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  description = "GitHub org/username that owns the repo, e.g. Damola12345"
  type        = string
}

variable "github_repo" {
  type    = string
  default = "finzla-platform"
}

# GitHub's OIDC token `sub` claim can (and, for some accounts/orgs,
# apparently does by default) include the org's and repo's immutable
# numeric IDs alongside their names, e.g.
#   repo:Damola12345@82381308/aws-cloud-platform@1347051150:pull_request
# instead of the "classic" repo:OWNER/REPO:pull_request. A trust policy
# built only from names never matches that format at all - every
# AssumeRoleWithWebIdentity call is silently rejected regardless of how
# correct everything else is, which is exactly what happened here (see
# CloudTrail: every denied event showed this ID-suffixed subject).
#
# Find these values with:
#   gh api user --jq .id                      (or: gh api orgs/<org> --jq .id)
#   gh api repos/<org>/<repo> --jq .id
# or read them directly off a denied AssumeRoleWithWebIdentity CloudTrail
# event's userIdentity.userName field, as done here.
variable "github_org_id" {
  description = "GitHub org/user's immutable numeric ID - see comment above for how to find it"
  type        = string
}

variable "github_repo_id" {
  description = "GitHub repo's immutable numeric ID - see comment above for how to find it"
  type        = string
}

locals {
  environments = ["dev", "prod"]
  project      = "finzla"
}

# tfsec flags this bucket for missing access logging
# (aws-s3-enable-bucket-logging, MEDIUM) - accepted deliberately for now: a
# dedicated logging bucket (S3 access logs must target a separate bucket,
# never the same one) adds a second bucket, its own lifecycle policy, and a
# log-delivery bucket policy purely to audit access to a Terraform state
# bucket only ever touched by this project's own IAM roles and a human's
# scoped bootstrap credentials - no other principal in the account can
# reach it at all (see the public-access-block below). Worth revisiting if
# more people/roles ever get access to this account.
#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "state" {
  for_each = toset(local.environments)
  bucket   = "finzla-terraform-state-${each.value}"

  tags = { Purpose = "terraform-remote-state", Environment = each.value }
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = aws_s3_bucket.state
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled" # every state write is recoverable
  }
}

# tfsec flags aws:kms (AWS-managed key) here as not customer-managed
# (aws-s3-encryption-customer-key, HIGH) - accepted deliberately: a
# customer-managed KMS key would mean creating and rotating a key plus
# extending every IAM role that touches state (github_ci, terraform_apply,
# a human's bootstrap credentials) with kms:Decrypt/GenerateDataKey grants,
# for a bucket that deliberately never contains secrets (see README's
# Security section) - the marginal confidentiality gain over AWS-managed
# KMS encryption is small relative to that added surface area for this
# project's scope. Worth reconsidering if this bucket ever needs to satisfy
# a compliance requirement that specifically mandates customer-managed keys.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = aws_s3_bucket.state
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each                = aws_s3_bucket.state
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explicit rather than relying on DynamoDB's default at-rest encryption:
# makes the security posture visible in code/plan output rather than an
# implicit platform default someone has to already know about.
# tfsec attributes its customer-key finding to this WHOLE resource, not the
# nested server_side_encryption block below - the ignore has to sit here,
# not there, for the same reason as github_ci_permissions in iam-pr-plan.tf
# (tfsec's ignore-matching only recognizes a comment directly above the
# block it actually reports the finding against).
# Same trade-off as the S3 bucket's encryption (AWS-managed key, not
# customer-managed) - tfsec: aws-dynamodb-table-customer-key, LOW. This
# table holds only lock IDs, never state content itself.
#tfsec:ignore:aws-dynamodb-table-customer-key
resource "aws_dynamodb_table" "locks" {
  for_each     = toset(local.environments)
  name         = "finzla-terraform-locks-${each.value}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  # Cheap and genuinely useful for a lock table specifically: if a lock
  # record is ever accidentally or maliciously deleted, this recovers it
  # rather than leaving Terraform state briefly unlockable. Negligible cost
  # at this table's throughput.
  point_in_time_recovery {
    enabled = true
  }

  tags = { Purpose = "terraform-state-locking", Environment = each.value }
}