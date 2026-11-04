output "alb_dns_name" {
  description = "DR ALB DNS name for Route 53 failover record"
  value       = aws_lb.dr.dns_name
}

output "alb_zone_id" {
  description = "DR ALB hosted zone ID for Route 53 alias record"
  value       = aws_lb.dr.zone_id
}

output "replica_endpoint" {
  description = "DR RDS read replica endpoint — becomes primary on promotion"
  value       = aws_db_instance.dr_replica.endpoint
}

output "asg_name" {
  description = "DR ASG name — set desired_capacity=1 during failover"
  value       = aws_autoscaling_group.dr.name
}

output "replica_identifier" {
  description = "DR RDS identifier — used in promote command"
  value       = aws_db_instance.dr_replica.identifier
}
