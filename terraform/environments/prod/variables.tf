variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "project" {
  type    = string
  default = "finzla"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
}

variable "domain_name" {
  description = "Root domain already hosted as a public zone in Route53, e.g. dxxxx.com - also used to look up an already-issued ACM certificate for the ALB (must be ISSUED and cover this domain or a wildcard over it, in the same region as aws_region)"
  type        = string
  default     = "dxxxx.com"
}

variable "app_hostname" {
  description = "Full hostname to create and point at the ALB, e.g. finzla.dxxxx.com. Must fall under domain_name (or its wildcard)."
  type        = string
  default     = "finzla.dxxxx.com"
}

variable "create_dns_record" {
  description = "Set false if domain_name isn't hosted in this AWS account's Route53 (e.g. reusing this module elsewhere) - you'll then need to point DNS at alb_dns_name manually."
  type        = bool
  default     = true
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type    = string
  default = "aws-cloud-platform"
}

variable "github_org_id" {
  description = "GitHub org/user's immutable numeric ID"
  type        = string
}

variable "github_repo_id" {
  description = "GitHub repo's immutable numeric ID"
  type        = string
}


variable "alarm_email" {
  type = string
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "log_retention_days" {
  description = "Longer retention in prod for audit/incident-review purposes on a fintech workload"
  type        = number
  default     = 90
}
