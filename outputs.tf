output "primary_alb_dns" {
  description = "Primary ALB — normal traffic endpoint"
  value       = module.primary.alb_dns_name
}

output "dr_alb_dns" {
  description = "DR ALB — active on failover"
  value       = module.dr.alb_dns_name
}

output "primary_db_endpoint" {
  description = "Primary RDS endpoint"
  value       = module.primary.db_endpoint
}

output "dr_replica_endpoint" {
  description = "DR read replica — promote this on failover"
  value       = module.dr.replica_endpoint
}

output "dr_asg_name" {
  description = "DR ASG — set desired_capacity=1 to activate pilot light"
  value       = module.dr.asg_name
}

output "dr_replica_identifier" {
  description = "RDS identifier used to promote: aws rds promote-read-replica --db-instance-identifier <this>"
  value       = module.dr.replica_identifier
}

output "app_url" {
  description = "App DNS via Route 53 failover"
  value       = "http://${module.route53_failover.app_fqdn}"
}

output "health_check_alarm" {
  description = "CloudWatch alarm name — fires when primary fails health check"
  value       = module.route53_failover.cloudwatch_alarm_name
}
