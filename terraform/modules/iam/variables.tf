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

variable "github_org_id" {
  description = "GitHub org/user's immutable numeric ID"
  type        = string
}

variable "github_repo_id" {
  description = "GitHub repo's immutable numeric ID"
  type        = string
}

variable "environment" {
  description = "dev or prod - used for resource naming (e.g. finzla-dev-cluster)"
  type        = string
}

# Separate from `environment` above on purpose: `environment` drives AWS
# resource naming ("dev"/"prod"), but the actual GitHub Environment
# deploy.yml's jobs declare is named "development"/"production" - these
# were silently assumed to be the same string and weren't, which broke
# github_deploy's OIDC trust condition (it requires an exact match).
variable "github_environment" {
  description = "The exact GitHub Environment name (e.g. \"development\", \"production\") that deploy.yml's jobs declare - must match exactly, this is a StringEquals condition"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}