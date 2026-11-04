variable "app_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "primary_db_arn" {
  type        = string
  description = "ARN of primary RDS — used to create cross-region read replica"
}

variable "db_instance_class" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}
