
terraform {
  backend "s3" {
    bucket         = "finzla-terraform-state-dev" # created by terraform/bootstrap
    key            = "finzla-platform/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "finzla-terraform-locks-dev"
    encrypt        = true
  }
}
