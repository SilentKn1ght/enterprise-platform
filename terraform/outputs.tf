output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

#output "ecs_cluster_name" {
#  description = "ECS cluster name"
#  value       = module.ecs.cluster_name
#}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

#output "ecr_repository_url" {
#  description = "ECR repository URL"
#  value       = module.ecs.ecr_repository_url
#}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_url" {
  description = "URL to access the application"
  value       = "http://${module.alb.alb_dns_name}"
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = module.alb.target_group_arn
}

output "rds_address" {
  description = "RDS database address"
  value       = module.rds.db_address
}

output "database_name" {
  description = "Database name"
  value       = module.rds.db_name
}

output "aws_region" {
  value = var.aws_region
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecs.ecr_repository_url
}