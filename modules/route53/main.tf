# ============================================================
# ROUTE 53 — Failover Routing Policy
#
# How it works:
#   PRIMARY record: active health check on primary ALB /health
#   SECONDARY record: no health check — passive failover target
#
# When primary health check fails 3 consecutive checks:
#   → Route 53 stops resolving PRIMARY record
#   → All DNS resolves to SECONDARY (DR ALB)
#   → Traffic hits DR ALB → DR ASG must already be scaling up
# ============================================================

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.primary, aws.dr]
    }
  }
}

# ------------------------------------------------------------
# Hosted Zone (must already exist — we just look it up)
# ------------------------------------------------------------
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ------------------------------------------------------------
# Route 53 Health Check — monitors primary ALB /health
# ------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_endpoint
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "${var.app_name}-primary-health-check"
    Role = "failover-trigger"
  }
}

# ------------------------------------------------------------
# PRIMARY failover record — active, health-checked
# ------------------------------------------------------------
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_endpoint
    zone_id                = var.primary_zone_id
    evaluate_target_health = true
  }
}

# ------------------------------------------------------------
# SECONDARY failover record — passive DR target
# No health check — becomes active only when primary fails
# ------------------------------------------------------------
resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"

  alias {
    name                   = var.dr_endpoint
    zone_id                = var.dr_zone_id
    evaluate_target_health = false   # DR is standby; skip health check on the passive record
  }
}

# ------------------------------------------------------------
# CloudWatch Alarm — alert when health check fails
# ------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "primary_health" {
  alarm_name          = "${var.app_name}-primary-health-check-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Primary region health check failed — DR failover may be active"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  tags = { Name = "${var.app_name}-health-alarm" }
}
