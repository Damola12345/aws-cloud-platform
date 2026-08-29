

terraform {
  backend "s3" {
    bucket         = "finzla-terraform-state-prod" # created by terraform/bootstrap
    key            = "finzla-platform/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "finzla-terraform-locks-prod"
    encrypt        = true
  }
}
