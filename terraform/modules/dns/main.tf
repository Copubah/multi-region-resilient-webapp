# Route 53 Hosted Zone (only create in primary region)
resource "aws_route53_zone" "main" {
  count = var.is_primary ? 1 : 0

  name = var.domain_name

  tags = {
    Name        = "${var.project_name}-hosted-zone"
    Environment = "global"
  }
}

# Health Check for Primary Region
resource "aws_route53_health_check" "primary" {
  count = var.is_primary ? 1 : 0

  fqdn                            = var.primary_alb_dns_name
  port                            = 80
  type                            = "HTTP"
  resource_path                   = "/health"
  failure_threshold               = 3
  request_interval                = 30
  cloudwatch_alarm_region         = var.primary_region
  cloudwatch_alarm_name           = "${var.project_name}-primary-health-alarm"
  insufficient_data_health_status = "Failure"

  tags = {
    Name = "${var.project_name}-primary-health-check"
  }
}

# Health Check for Secondary Region
resource "aws_route53_health_check" "secondary" {
  count = var.is_primary ? 1 : 0

  fqdn                            = var.secondary_alb_dns_name
  port                            = 80
  type                            = "HTTP"
  resource_path                   = "/health"
  failure_threshold               = 3
  request_interval                = 30
  cloudwatch_alarm_region         = var.secondary_region
  cloudwatch_alarm_name           = "${var.project_name}-secondary-health-alarm"
  insufficient_data_health_status = "Failure"

  tags = {
    Name = "${var.project_name}-secondary-health-check"
  }
}

# Primary DNS Record (Failover Primary)
resource "aws_route53_record" "primary" {
  count = var.is_primary ? 1 : 0

  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary[0].id

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# Secondary DNS Record (Failover Secondary)
resource "aws_route53_record" "secondary" {
  count = var.is_primary ? 1 : 0

  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  set_identifier = "secondary"
  failover_routing_policy {
    type = "SECONDARY"
  }

  health_check_id = aws_route53_health_check.secondary[0].id

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}

# WWW CNAME Record
resource "aws_route53_record" "www" {
  count = var.is_primary ? 1 : 0

  zone_id = aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]
}