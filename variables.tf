variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster Recovery AWS region"
  type        = string
  default     = "us-west-2"
}

variable "app_name" {
  description = "Application name used for resource naming"
  type        = string
  default     = "eli-dr-lab"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "portfolio"
}

variable "primary_instance_type" {
  description = "EC2 instance type for primary region"
  type        = string
  default     = "t3.micro"
}

variable "dr_instance_type" {
  description = "EC2 instance type for DR region (pilot light — same size, starts stopped)"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "appuser"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Route 53 hosted zone domain (must already exist in your account)"
  type        = string
  default     = "eli-dr-lab.internal"
}

variable "health_check_path" {
  description = "HTTP path Route 53 uses for the primary health check"
  type        = string
  default     = "/health"
}
