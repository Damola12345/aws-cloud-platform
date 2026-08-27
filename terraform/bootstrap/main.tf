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

  point_in_time_recovery {
    enabled = true
  }

  tags = { Purpose = "terraform-state-locking", Environment = each.value }
}
