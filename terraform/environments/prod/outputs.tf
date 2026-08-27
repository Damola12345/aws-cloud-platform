output "alb_dns_name" {
  description = "Raw AWS-assigned DNS name of the load balancer"
  value       = module.alb.alb_dns_name
}

output "app_url" {
  description = "The actual URL to hit once the Route53 record has propagated"
  value       = var.create_dns_record ? "https://${var.app_hostname}" : "https://${module.alb.alb_dns_name} (no DNS record created - see create_dns_record)"
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = local.cluster_name
}

output "ecs_service_name" {
  value = local.service_name
}

output "github_deploy_role_arn" {
  description = "Set as AWS_DEPLOY_ROLE_ARN_PROD in GitHub. (AWS_CI_ROLE_ARN comes from terraform/bootstrap's output instead.)"
  value       = module.iam.github_deploy_role_arn
}

output "log_group_name" {
  value = module.monitoring.log_group_name
}