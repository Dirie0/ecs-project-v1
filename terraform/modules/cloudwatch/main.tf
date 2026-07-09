resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/${var.environment}/app"
  retention_in_days = 30

  tags = merge(
    var.common_tags,
    {
      Name    = "${var.project_name}-${var.environment}-app-log-group"
      Service = "cloudwatch"
    }
  )
}

