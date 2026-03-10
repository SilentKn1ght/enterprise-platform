# CloudWatch and SNS variables for monitoring

variable "alert_email" {
  description = "Email address for receiving CloudWatch alarms"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "db_instance_id" {
  description = "RDS database instance identifier"
  type        = string
  default     = ""
}

variable "alb_name" {
  description = "Name of the Application Load Balancer"
  type        = string
  default     = ""
}

variable "target_group_name" {
  description = "Name of the ALB target group"
  type        = string
  default     = ""
}
