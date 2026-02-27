variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ECS tasks security group ID"
  type        = string
}

variable "app_port" {
  description = "Application port"
  type        = number
}

variable "app_count" {
  description = "Number of ECS tasks"
  type        = number
}

variable "fargate_cpu" {
  description = "Fargate CPU units"
  type        = number
}

variable "fargate_memory" {
  description = "Fargate memory in MB"
  type        = number
}

variable "target_group_arn" {
  description = "ALB target group ARN"
  type        = string
}

variable "alb_listener" {
  description = "ALB listener (for depends_on)"
  type        = any
}

variable "db_endpoint" {
  description = "Database endpoint"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password_secret_arn" {
  description = "ARN of secret containing database password"
  type        = string
}

variable "use_load_balancer" {
  description = "Whether to attach to load balancer"
  type        = bool
  default     = false
}

variable "min_tasks" {
  description = "Minimum number of tasks"
  type        = number
  default     = 2
}

variable "max_tasks" {
  description = "Maximum number of tasks"
  type        = number
  default     = 10
}

variable "cpu_scale_up_threshold" {
  description = "CPU percentage to trigger scale up"
  type        = number
  default     = 70
}

variable "cpu_scale_down_threshold" {
  description = "CPU percentage to trigger scale down"
  type        = number
  default     = 30
}

variable "container_name" {
  type    = string
  default = "api"
}