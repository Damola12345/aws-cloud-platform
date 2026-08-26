output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "github_ci_role_arn" {
  value = aws_iam_role.github_ci.arn
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
