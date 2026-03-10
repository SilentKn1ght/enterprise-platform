# Grafana ECS Task Definition and Service Configuration

# Log group for Grafana
resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project_name}-${var.environment}-grafana"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Grafana Task Definition
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-${var.environment}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.grafana_task_execution.arn
  task_role_arn            = aws_iam_role.grafana_task.arn

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "grafana/grafana:10.2.2"

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "GF_SECURITY_ADMIN_USER"
          value = "admin"
        },
        {
          name  = "GF_SERVER_ROOT_URL"
          value = "http://localhost:3000"
        },
        {
          name  = "GF_INSTALL_PLUGINS"
          value = "grafana-cloudwatch-datasource"
        },
        {
          name  = "GF_SECURITY_ALLOW_EMBED_INIT_STATE_IN_VIEW_MODE"
          value = "true"
        }
      ]

      secrets = [
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.grafana_password.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "grafana"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      mountPoints = [
        {
          sourceVolume  = "grafana-storage"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ]
    }
  ])

  volume {
    name = "grafana-storage"
    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.grafana.id
      transit_encryption     = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana.id
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-task"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [
    aws_iam_role.grafana_task_execution,
    aws_iam_role.grafana_task
  ]
}

# Grafana Task Execution Role
resource "aws_iam_role" "grafana_task_execution" {
  name = "${var.project_name}-${var.environment}-grafana-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach basic ECS execution policy
resource "aws_iam_role_policy_attachment" "grafana_task_execution" {
  role       = aws_iam_role.grafana_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow pulling Grafana password from Secrets Manager
resource "aws_iam_role_policy" "grafana_task_execution_secrets" {
  name   = "${var.project_name}-${var.environment}-grafana-secrets-policy"
  role   = aws_iam_role.grafana_task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.grafana_password.arn
        ]
      }
    ]
  })
}

# Grafana Task Role (for accessing CloudWatch)
resource "aws_iam_role" "grafana_task" {
  name = "${var.project_name}-${var.environment}-grafana-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Allow Grafana to read CloudWatch metrics and logs
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name   = "${var.project_name}-${var.environment}-grafana-cloudwatch-policy"
  role   = aws_iam_role.grafana_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeMetricAlarms",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# Grafana password in Secrets Manager
resource "aws_secretsmanager_secret" "grafana_password" {
  name                    = "${var.project_name}-${var.environment}-grafana-password"
  description             = "Admin password for Grafana"
  recovery_window_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Generate and store random password
resource "aws_secretsmanager_secret_version" "grafana_password" {
  secret_id       = aws_secretsmanager_secret.grafana_password.id
  secret_string   = var.grafana_password != "" ? var.grafana_password : random_password.grafana.result
}

# Random password generation if not provided
resource "random_password" "grafana" {
  length  = 16
  special = true
}

# EFS for Grafana persistent storage
resource "aws_efs_file_system" "grafana" {
  creation_token = "${var.project_name}-${var.environment}-grafana"
  encrypted      = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-efs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EFS Access Point for Grafana
resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.grafana.id

  posix_user {
    gid = 472  # Grafana GID
    uid = 472  # Grafana UID
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "700"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-grafana-ap"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "grafana" {
  for_each           = toset(var.private_subnet_ids)
  file_system_id     = aws_efs_file_system.grafana.id
  subnet_id          = each.value
  security_groups    = [aws_security_group.grafana_efs.id]
}

# Security Group for EFS
resource "aws_security_group" "grafana_efs" {
  name        = "${var.project_name}-${var.environment}-grafana-efs-sg"
  description = "Security group for Grafana EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana_ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-efs-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Security Group for Grafana ECS tasks
resource "aws_security_group" "grafana_ecs" {
  name        = "${var.project_name}-${var.environment}-grafana-sg"
  description = "Security group for Grafana ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow Grafana access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Grafana ECS Service
resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-${var.environment}-grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.grafana_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener_rule.grafana,
    aws_efs_mount_target.grafana
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-service"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ALB Target Group for Grafana
resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-${var.environment}-grafana"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ALB Listener Rule for Grafana Path
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = var.alb_listener
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana*"]
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana-rule"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Data source for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Outputs
output "grafana_log_group" {
  value       = aws_cloudwatch_log_group.grafana.name
  description = "Grafana CloudWatch log group"
}

output "grafana_efs_id" {
  value       = aws_efs_file_system.grafana.id
  description = "Grafana EFS file system ID"
}

output "grafana_service_name" {
  value       = aws_ecs_service.grafana.name
  description = "Grafana ECS service name"
}

output "grafana_password_secret" {
  value       = aws_secretsmanager_secret.grafana_password.name
  description = "Secrets Manager secret for Grafana password"
  sensitive   = true
}
