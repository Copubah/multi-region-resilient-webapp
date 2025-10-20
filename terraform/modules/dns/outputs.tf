output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone"
  value       = var.is_primary ? aws_route53_zone.main[0].zone_id : ""
}

output "name_servers" {
  description = "Name servers for the hosted zone"
  value       = var.is_primary ? aws_route53_zone.main[0].name_servers : []
}

output "primary_health_check_id" {
  description = "ID of the primary health check"
  value       = var.is_primary ? aws_route53_health_check.primary[0].id : ""
}

output "secondary_health_check_id" {
  description = "ID of the secondary health check"
  value       = var.is_primary ? aws_route53_health_check.secondary[0].id : ""
}