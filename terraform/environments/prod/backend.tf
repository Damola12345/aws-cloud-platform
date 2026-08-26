# Remote state in S3 with a DynamoDB lock table (S3-native locking is also an
# option on newer Terraform/provider versions, but DynamoDB is used here for
# broad compatibility - see terraform/bootstrap/ for how these are created).
#
# Values are intentionally left as placeholders: they are account-specific
# and are populated once via `terraform init -backend-config=...` or by
# filling this file in after running the bootstrap. Nothing here is a secret.

terraform {
  backend "s3" {
    bucket         = "finzla-terraform-state-prod"    # created by terraform/bootstrap
    key            = "finzla-platform/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "finzla-terraform-locks-prod"
    encrypt        = true
  }
}
