resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  # SSE-managed by CloudWatch Logs by default; swap in a customer KMS key
  # here (kms_key_id) if the org's key policy requires CMKs for all logs.

  tags = var.tags
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -----------------------------------------------------------------------------
# Alarm 1: HTTP 5xx error rate from the target group (application errors).
# Fires fast (2 of 3 breaching evaluations, 1 minute periods) because 5xx
# directly means customers are getting broken responses right now.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name}-target-5xx-rate"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_description = "More than 5 HTTP 5xx responses from application targets in a 3-minute window."
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Alarm 2: Unhealthy target count - the ALB itself is failing /health checks.
# This is the earliest reliable signal of a bad deploy (see the troubleshooting
# scenario: "AWS reports tasks running" but targets are unhealthy).
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${var.name}-unhealthy-targets"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_description  = "One or more ECS targets are failing ALB health checks."
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Alarm 3: ECS service running task count below the configured minimum -
# catches capacity loss even when the ALB metrics above haven't caught up yet
# (e.g. tasks crash-looping before ever registering as healthy).
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "running_task_count_low" {
  alarm_name          = "${var.name}-running-task-count-low"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_description  = "Fewer than 1 healthy task running - service is at risk of a full outage."
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Additional metrics we track on the dashboard but don't page on directly -
# useful during investigation rather than as a trigger of their own.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.name}-high-cpu"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_description  = "Sustained high CPU - informational/capacity signal, not paged urgently (autoscaling should react first)."
  alarm_actions      = [aws_sns_topic.alerts.arn]

  tags = var.tags
}
