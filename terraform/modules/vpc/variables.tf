variable "name" {
  description = "Name prefix for all VPC resources, e.g. finzla-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB), one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (ECS tasks), one per AZ"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway instead of one per AZ. Cheaper, less resilient - suitable for dev."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
