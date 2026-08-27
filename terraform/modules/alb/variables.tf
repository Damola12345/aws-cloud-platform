variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Must already exist / be validated."
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the ALB on 443. Defaults to the public internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
