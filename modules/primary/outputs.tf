output "alb_dns_name" {
  description = "Primary ALB DNS name for Route 53 failover record"
  value       = aws_lb.primary.dns_name
}

output "alb_zone_id" {
  description = "Primary ALB hosted zone ID for Route 53 alias record"
  value       = aws_lb.primary.zone_id
}

output "db_instance_arn" {
  description = "Primary RDS ARN — used by DR module to create cross-region read replica"
  value       = aws_db_instance.primary.arn
}

output "db_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "vpc_id" {
  value = aws_vpc.primary.id
}
