# Grafana-specific variables

variable "grafana_password" {
  description = "Grafana admin password (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "grafana_deploy" {
  description = "Whether to deploy Grafana to ECS"
  type        = bool
  default     = true
}
