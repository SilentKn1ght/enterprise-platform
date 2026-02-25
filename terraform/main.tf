terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state (we'll set this up later)
  # backend "s3" {
  #   bucket = "enterprise-platform-terraform-state"
  #   key    = "prod/terraform.tfstate"
  #   region = "eu-north-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Enterprise Platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  app_port           = var.app_port
}

module "alb" {
  source = "./modules/alb"

  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id

  app_port          = 3000
  health_check_path = "/health"
  environment       = var.environment
  project_name      = var.project_name
}

module "ecs" {
  source = "./modules/ecs"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  ecs_security_group_id = module.networking.ecs_tasks_security_group_id

  app_port       = var.app_port
  app_count      = var.app_count
  fargate_cpu    = var.fargate_cpu
  fargate_memory = var.fargate_memory

  target_group_arn  = module.alb.target_group_arn
  alb_listener      = module.alb.http_listener_arn
  use_load_balancer = true

  db_endpoint            = module.rds.db_endpoint
  db_name                = var.db_name
  db_username            = var.db_username
  db_password_secret_arn = module.rds.db_password_secret_arn
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  rds_security_group_id = module.networking.rds_security_group_id

  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  db_instance_class = var.db_instance_class

  environment  = var.environment
  project_name = var.project_name
}
