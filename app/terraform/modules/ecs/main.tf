resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.project_name}-${var.environment}-cluster"
  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-cluster"
      Service = "ecs"
    }
  )
}

resource "aws_ecs_task_definition" "ecs_gatus_task" {
  family = "${var.project_name}-task"
  execution_role_arn = var.ecs_execution_role_arn
  task_role_arn = var.ecs_task_role_arn
  network_mode       = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = var.task_cpu
  memory = var.task_memory
  container_definitions = templatefile(
    "${path.module}/templates/ecs_task_definition.json",
    {
      project_name      = var.project_name
      app_port          = var.app_port
      ecr_repository_url = var.ecr_repository_url
      task_cpu          = var.task_cpu
      task_memory       = var.task_memory
      app_image = var.app_image
      aws_region = var.aws_region
      log_group= var.log_group
      environment = var.environment

    }
  )
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
}

#ecs service
resource "aws_ecs_service" "ecs_gatus_service" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_gatus_task.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "${var.environment}-ecs-${var.project_name}-container"
    container_port   = var.app_port
  }
 depends_on = [  ]
  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-ecs-service"
      Service = "ecs"
    }
  )
}