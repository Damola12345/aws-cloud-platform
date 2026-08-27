variable "name" {
  description = "ECR repository name, e.g. finzla-dev-app"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
