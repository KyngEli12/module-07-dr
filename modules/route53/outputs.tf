output "health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "app_fqdn" {
  value = aws_route53_record.primary.fqdn
}

output "cloudwatch_alarm_name" {
  value = aws_cloudwatch_metric_alarm.primary_health.alarm_name
}
