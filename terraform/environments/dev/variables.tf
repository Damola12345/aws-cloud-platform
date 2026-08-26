variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "finzla"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.0.0/24", "10.10.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "domain_name" {
  description = "Root domain already hosted as a public zone in Route53, e.g. damola.com - also used to look up an already-issued ACM certificate for the ALB (must be ISSUED and cover this domain or a wildcard over it, in the same region as aws_region)"
  type        = string
  default     = "damola.com"
}

variable "app_hostname" {
  description = "Full hostname to create and point at the ALB, e.g. finzla-dev.damola.com. Must fall under domain_name (or its wildcard)."
  type        = string
  default     = "finzla-dev.damola.com"
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
  default = "finzla-platform"
}

variable "alarm_email" {
  type = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 2
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "log_retention_days" {
  type    = number
  default = 14
}
