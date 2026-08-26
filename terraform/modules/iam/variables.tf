variable "name" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster the GitHub role is allowed to deploy into"
  type        = string
}

variable "ecs_service_arn" {
  description = "ARN of the specific ECS service the GitHub role is allowed to update"
  type        = string
}

variable "log_group_arn" {
  type = string
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repo, e.g. octocat"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name, e.g. finzla-platform"
  type        = string
}

variable "environment" {
  description = "dev or prod - used to scope the GitHub OIDC trust condition"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
