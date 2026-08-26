variable "name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "https_listener_arn" {
  description = "Forces the service to wait for the listener to exist before registering targets"
  type        = string
}

variable "ecr_repository_url" {
  type = string
}

variable "image_tag" {
  description = "Immutable image tag to deploy, e.g. a git SHA. Overridden by CI at deploy time."
  type        = string
  default     = "latest"
}

variable "build_number" {
  description = "CI build number. Set by Terraform only for the very first task definition revision - every deploy after that is rewritten directly by the CI pipeline (see .github/actions/ecs-deploy), which is why the ECS service has lifecycle.ignore_changes on task_definition."
  type        = string
  default     = "terraform-initial"
}

variable "git_commit" {
  description = "Git commit the running image was built from. Same caveat as build_number above."
  type        = string
  default     = "unknown"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
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
  default = 4
}

variable "app_env" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
