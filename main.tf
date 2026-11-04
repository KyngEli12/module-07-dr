terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for real deployments
  # backend "s3" {
  #   bucket = "your-tfstate-bucket"
  #   key    = "module-07-dr/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ------------------------------------------------------------
# Provider aliases — one per region
# ------------------------------------------------------------
provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
}

# Route 53 health checks must be created in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# ------------------------------------------------------------
# PRIMARY REGION  (us-east-1)
# ------------------------------------------------------------
module "primary" {
  source = "./modules/primary"

  providers = {
    aws = aws.primary
  }

  app_name      = var.app_name
  environment   = var.environment
  instance_type = var.primary_instance_type
  db_instance_class = var.db_instance_class
  db_name       = var.db_name
  db_username   = var.db_username
  db_password   = var.db_password
}

# ------------------------------------------------------------
# DR REGION  (us-west-2)  — Pilot Light
# Minimal footprint: AMI baked, instance STOPPED, RDS read replica RUNNING
# On failover: start instance, promote replica, Route 53 flips
# ------------------------------------------------------------
module "dr" {
  source = "./modules/dr"

  providers = {
    aws = aws.dr
  }

  app_name            = var.app_name
  environment         = var.environment
  instance_type       = var.dr_instance_type
  primary_db_arn      = module.primary.db_instance_arn
  db_instance_class   = var.db_instance_class
  db_username         = var.db_username
  db_password         = var.db_password

  depends_on = [module.primary]
}

# ------------------------------------------------------------
# ROUTE 53 — Failover Routing
# Primary record → primary ALB (active health check)
# Secondary record → DR ALB (failover target, no health check)
# ------------------------------------------------------------
module "route53_failover" {
  source = "./modules/route53"

  providers = {
    aws            = aws.us_east_1
    aws.primary    = aws.primary
    aws.dr         = aws.dr
  }

  app_name            = var.app_name
  domain_name         = var.domain_name
  health_check_path   = var.health_check_path
  primary_endpoint    = module.primary.alb_dns_name
  dr_endpoint         = module.dr.alb_dns_name
  primary_zone_id     = module.primary.alb_zone_id
  dr_zone_id          = module.dr.alb_zone_id
}
