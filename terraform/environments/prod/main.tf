terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}

data "aws_acm_certificate" "this" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${local.name}-cluster"
  service_name = "${local.name}-service"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  ecs_cluster_arn = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"
  ecs_service_arn = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${local.cluster_name}/${local.service_name}"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name                  = local.name
  vpc_cidr              = var.vpc_cidr
  azs                   = var.azs
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  single_nat_gateway    = false # prod: one NAT per AZ - resilience over cost
  tags                  = local.tags
}

# ---------------------------------------------------------------------------
# Image repository
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  name = "${local.name}-app"
  tags = local.tags
}

# ---------------------------------------------------------------------------
# Ingress
# ---------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  container_port    = var.container_port
  certificate_arn   = data.aws_acm_certificate.this.arn
  tags              = local.tags
}

module "dns" {
  source = "../../modules/dns"
  count  = var.create_dns_record ? 1 : 0

  domain_name  = var.domain_name
  record_name  = var.app_hostname
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
}

# ---------------------------------------------------------------------------
# Logging & alerting (created before IAM/ECS so both can reference it)
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  name                     = local.name
  log_retention_days       = var.log_retention_days
  alarm_email              = var.alarm_email
  alb_arn_suffix           = module.alb.alb_arn_suffix
  target_group_arn_suffix  = module.alb.target_group_arn_suffix
  ecs_cluster_name         = local.cluster_name
  ecs_service_name         = local.service_name
  tags                     = local.tags
}

# ---------------------------------------------------------------------------
# IAM (least privilege ECS + scoped GitHub OIDC roles)
# ---------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  name                  = local.name
  ecr_repository_arn    = module.ecr.repository_arn
  ecs_cluster_arn       = local.ecs_cluster_arn
  ecs_service_arn       = local.ecs_service_arn
  log_group_arn         = module.monitoring.log_group_arn
  github_org            = var.github_org
  github_repo           = var.github_repo
  environment           = var.environment
  tags                  = local.tags
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------
module "ecs" {
  source = "../../modules/ecs"

  name                   = local.name
  cluster_name           = local.cluster_name
  service_name           = local.service_name
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  alb_security_group_id  = module.alb.alb_security_group_id
  target_group_arn       = module.alb.target_group_arn
  https_listener_arn     = module.alb.https_listener_arn
  ecr_repository_url     = module.ecr.repository_url
  container_port         = var.container_port
  desired_count           = var.desired_count
  min_capacity            = var.min_capacity
  max_capacity            = var.max_capacity
  app_env                 = var.environment
  execution_role_arn      = module.iam.ecs_task_execution_role_arn
  task_role_arn            = module.iam.ecs_task_role_arn
  log_group_name           = module.monitoring.log_group_name
  aws_region                = var.aws_region
  tags                      = local.tags
}
