variable "name" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alarm_email" {
  description = "Email address to subscribe to the alerts SNS topic"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (aws_lb.this.arn_suffix), required by CloudWatch metric dimensions"
  type        = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
