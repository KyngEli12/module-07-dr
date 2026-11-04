variable "app_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "health_check_path" {
  type = string
}

variable "primary_endpoint" {
  type        = string
  description = "Primary ALB DNS name"
}

variable "dr_endpoint" {
  type        = string
  description = "DR ALB DNS name"
}

variable "primary_zone_id" {
  type        = string
  description = "Primary ALB hosted zone ID"
}

variable "dr_zone_id" {
  type        = string
  description = "DR ALB hosted zone ID"
}
