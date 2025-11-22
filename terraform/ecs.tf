#########################
# IAM for ECS
#########################

# Execution role: pulls image, writes logs, etc.
# resource "aws_iam_role" "ecs_task_execution" {
#   name = "${var.project_name}-ecs-task-execution-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect    = "Allow",
#         Principal = { Service = "ecs-tasks.amazonaws.com" },
#         Action    = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
#   role       = aws_iam_role.ecs_task_execution.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# # Task role: what the container itself can do (keep minimal for now)
# resource "aws_iam_role" "ecs_task" {
#   name = "${var.project_name}-ecs-task-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect    = "Allow",
#         Principal = { Service = "ecs-tasks.amazonaws.com" },
#         Action    = "sts:AssumeRole"
#       }
#     ]
#   })
# }

#########################
# CloudWatch Logs
#########################

resource "aws_cloudwatch_log_group" "ecs_spark" {
  name              = "/ecs/${var.project_name}-spark"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-ecs-logs"
  }
}

#########################
# ECS Cluster
#########################

resource "aws_ecs_cluster" "spark" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

#########################
# ECS Task Definition (Fargate)
#########################

resource "aws_ecs_task_definition" "spark" {
  family                   = "${var.project_name}-spark-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"  # 1 vCPU
  memory                   = "4096"  # 4 GB

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  # EFS volume via access point
  volume {
    name = "efs-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.spark.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "spark-job"
      image     = var.ecs_spark_image
      essential = true

      # Your Dockerfile should already start NYUTaxiSparkJob.py;
      # if not, you can set "command" here later.

      environment = [
        {
          name  = "DB_URL"
          value = "jdbc:postgresql://${aws_db_instance.rds.endpoint}/${aws_db_instance.rds.db_name}"
        }
        # Add more envs if you want to override config.json later
      ]

      "portMappings": [
        {
            "containerPort": 4040,
            "hostPort": 4040,
            "protocol": "tcp"
        }
    ]

      mountPoints = [
        {
          sourceVolume  = "efs-volume"
          containerPath = "/mnt/efs"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_spark.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "spark"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-spark-task"
  }

  depends_on = [
    aws_efs_mount_target.private
  ]
}

#########################
# ECS Service
#########################

resource "aws_ecs_service" "spark" {
  name            = "${var.project_name}-spark-service"
  cluster         = aws_ecs_cluster.spark.id
  task_definition = aws_ecs_task_definition.spark.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [for s in aws_subnet.public : s.id]
    security_groups = [aws_security_group.main.id]
    assign_public_ip = true
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  propagate_tags = "SERVICE"

  tags = {
    Name = "${var.project_name}-spark-service"
  }

  depends_on = [
    aws_ecs_task_definition.spark
  ]
}
