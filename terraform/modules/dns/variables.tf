variable "domain_name" {
  description = "Root domain already hosted in Route53, e.g. damola.com. Must exist as a public hosted zone in this AWS account."
  type        = string
}

variable "record_name" {
  description = "Full hostname to create, e.g. finzla-dev.damola.com"
  type        = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  description = "The ALB's own canonical hosted zone ID (aws_lb.this.zone_id), required for an ALIAS record - not your domain's Route53 zone ID"
  type        = string
}
