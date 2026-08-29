
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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