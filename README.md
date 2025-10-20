# Multi-Region Resilient Web Application

This project deploys a highly available, multi-region web application on AWS that automatically fails over between regions to ensure continuous uptime.

## Architecture Diagram

```
                                    ┌─────────────────────────────────────┐
                                    │             GLOBAL LAYER            │
                                    └─────────────────────────────────────┘
                                                      │
                                    ┌─────────────────▼─────────────────┐
                                    │           CloudFront CDN          │
                                    │     (Global Edge Locations)      │
                                    └─────────────────┬─────────────────┘
                                                      │
                                    ┌─────────────────▼─────────────────┐
                                    │           Route 53 DNS            │
                                    │    Health Checks & Failover       │
                                    └─────────────────┬─────────────────┘
                                                      │
                        ┌─────────────────────────────┼─────────────────────────────┐
                        │                             │                             │
                        ▼                             │                             ▼
            ┌───────────────────────────┐             │             ┌───────────────────────────┐
            │      PRIMARY REGION       │             │             │     SECONDARY REGION      │
            │       (us-east-1)         │             │             │       (us-west-2)         │
            └───────────────────────────┘             │             └───────────────────────────┘
                        │                             │                             │
            ┌───────────▼───────────┐                 │                 ┌───────────▼───────────┐
            │  Application Load     │                 │                 │  Application Load     │
            │     Balancer          │                 │                 │     Balancer          │
            │   (Multi-AZ: a,b,c)   │                 │                 │   (Multi-AZ: a,b,c)   │
            └───────────┬───────────┘                 │                 └───────────┬───────────┘
                        │                             │                             │
        ┌───────────────┼───────────────┐             │             ┌───────────────┼───────────────┐
        │               │               │             │             │               │               │
        ▼               ▼               ▼             │             ▼               ▼               ▼
    ┌───────┐       ┌───────┐       ┌───────┐         │         ┌───────┐       ┌───────┐       ┌───────┐
    │ AZ-1a │       │ AZ-1b │       │ AZ-1c │         │         │ AZ-2a │       │ AZ-2b │       │ AZ-2c │
    │       │       │       │       │       │         │         │       │       │       │       │       │
    │  ECS  │       │  ECS  │       │  ECS  │         │         │  ECS  │       │  ECS  │       │  ECS  │
    │Fargate│       │Fargate│       │Fargate│         │         │Fargate│       │Fargate│       │Fargate│
    │ Tasks │       │ Tasks │       │ Tasks │         │         │ Tasks │       │ Tasks │       │ Tasks │
    └───┬───┘       └───┬───┘       └───┬───┘         │         └───┬───┘       └───┬───┘       └───┬───┘
        │               │               │             │             │               │               │
        └───────────────┼───────────────┘             │             └───────────────┼───────────────┘
                        │                             │                             │
            ┌───────────▼───────────┐                 │                 ┌───────────▼───────────┐
            │    Aurora Global      │◄────────────────┼────────────────►│    Aurora Global      │
            │   Database Cluster    │                 │                 │   Database Cluster    │
            │     (Primary)         │   Replication   │                 │    (Secondary)        │
            │  Writer + Reader      │    < 1 sec      │                 │  Writer + Reader      │
            └───────────┬───────────┘                 │                 └───────────┬───────────┘
                        │                             │                             │
            ┌───────────▼───────────┐                 │                 ┌───────────▼───────────┐
            │      S3 Bucket        │◄────────────────┼────────────────►│      S3 Bucket        │
            │   (Static Assets)     │                 │                 │   (Static Assets)     │
            │ Cross-Region Repl     │   Replication   │                 │ Cross-Region Repl     │
            └───────────┬───────────┘                 │                 └───────────┬───────────┘
                        │                             │                             │
            ┌───────────▼───────────┐                 │                 ┌───────────▼───────────┐
            │     CloudWatch        │                 │                 │     CloudWatch        │
            │   Monitoring &        │                 │                 │   Monitoring &        │
            │     Alerting          │                 │                 │     Alerting          │
            └───────────────────────┘                 │                 └───────────────────────┘
                                                      │
                                    ┌─────────────────▼─────────────────┐
                                    │              SNS                  │
                                    │      Global Notifications         │
                                    │    (Email, SMS, Webhooks)         │
                                    └───────────────────────────────────┘
```

## Traffic Flow Scenarios

### Normal Operations (Primary Region Active)
```
User Request → CloudFront → Route 53 → Primary ALB → ECS Tasks → Aurora Primary → Response
     │              │           │           │            │            │
     │              │           │           │            │            └─ Read/Write Operations
     │              │           │           │            └─ FastAPI Application
     │              │           │           └─ Load Balance across AZs
     │              │           └─ DNS Resolution (Primary Healthy)
     │              └─ Edge Caching & SSL Termination
     └─ Global Users
```

### Failover Scenario (Primary Region Failed)
```
User Request → CloudFront → Route 53 → Secondary ALB → ECS Tasks → Aurora Secondary → Response
     │              │           │            │             │             │
     │              │           │            │             │             └─ Promoted to Primary
     │              │           │            │             └─ FastAPI Application
     │              │           │            └─ Load Balance across AZs
     │              │           └─ DNS Failover (Primary Unhealthy)
     │              └─ Origin Failover to Secondary
     └─ Seamless User Experience
```

## Architecture Overview

The application is deployed across two AWS regions (us-east-1 and us-west-2) with the following components:

- Web Application: FastAPI application running on ECS Fargate with multi-AZ deployment
- Database: Aurora Global Database with cross-region replication
- Storage: S3 buckets with cross-region replication for static assets
- DNS: Route 53 health checks and failover routing
- CDN: CloudFront distribution for global content delivery
- Monitoring: CloudWatch alarms and SNS notifications for failure detection

## Key Resilience Features

### High Availability Metrics
- Target Availability: 99.99% (four nines)
- RTO (Recovery Time Objective): < 5 minutes
- RPO (Recovery Point Objective): < 1 second
- Cross-Region Failover: Automatic via Route 53 health checks
- Multi-AZ Deployment: 3 availability zones per region

### Failure Scenarios Handled
```
┌─────────────────────┬──────────────────┬─────────────────┬──────────────────┐
│ Failure Type        │ Detection Time   │ Recovery Time   │ User Impact      │
├─────────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ Single Container    │ 30 seconds       │ < 2 minutes     │ None             │
│ Availability Zone   │ 30 seconds       │ < 1 minute      │ Minimal          │
│ Regional Database   │ 30 seconds       │ < 1 minute      │ Brief pause      │
│ Complete Region     │ 90 seconds       │ < 5 minutes     │ 2-5 min outage   │
└─────────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

### Automated Recovery Actions
- ECS Task Replacement: Unhealthy tasks automatically replaced
- Load Balancer Failover: Traffic routed away from failed targets
- Database Failover: Aurora promotes read replica to writer
- DNS Failover: Route 53 redirects traffic to healthy region
- S3 Replication: Static assets replicated across regions

## Project Structure

```
├── terraform/
│   ├── modules/
│   │   ├── networking/
│   │   ├── compute/
│   │   ├── database/
│   │   ├── storage/
│   │   ├── dns/
│   │   ├── cdn/
│   │   └── monitoring/
│   ├── environments/
│   │   ├── primary/
│   │   └── secondary/
│   └── global/
├── application/
│   └── fastapi-app/
├── docs/
└── scripts/
```

## Quick Start

### Automated Deployment (Recommended)
```bash
# One-command deployment
./scripts/deploy.sh --domain your-domain.com --email your-email@example.com
```

### Manual Deployment
1. Configure AWS credentials for both regions
2. Update variables in `terraform/environments/*/terraform.tfvars`
3. Deploy primary region: `cd terraform/environments/primary && terraform apply`
4. Deploy secondary region: `cd terraform/environments/secondary && terraform apply`
5. Update primary region: `cd terraform/environments/primary && terraform apply`

### Verify Deployment
```bash
# Test application health
curl https://your-domain.com/health

# Check current serving region
curl https://your-domain.com/api/status

# Test database connectivity
curl https://your-domain.com/api/data
```

## Testing and Monitoring

### Automated Failover Testing
```bash
# Run comprehensive failover test
./scripts/test-failover.sh --domain your-domain.com

# Monitor application during test
watch -n 10 'curl -s https://your-domain.com/api/status | jq ".region"'
```

### Monitoring Dashboards
- CloudWatch Dashboards: Real-time metrics for both regions
- Route 53 Health Checks: DNS failover monitoring
- ECS Service Metrics: Container health and performance
- Aurora Monitoring: Database performance and replication lag

### Key Endpoints
- Health Check: `https://your-domain.com/health`
- Application Status: `https://your-domain.com/api/status`
- Database Test: `https://your-domain.com/api/data`

## Documentation

- [Architecture Details](docs/architecture.md) - Comprehensive architecture explanation
- [Deployment Guide](docs/deployment-guide.md) - Step-by-step deployment instructions
- [Failover Testing](docs/failover-testing.md) - Complete testing procedures
- [Resilience Explanation](docs/resilience-explanation.md) - How each service contributes to resilience

## Cost Optimization

The architecture is designed for cost efficiency:
- ECS Fargate: Pay only for running containers
- Aurora Serverless: Automatic scaling based on demand
- S3 Intelligent Tiering: Automatic cost optimization
- CloudFront: Reduced origin server load

Estimated monthly cost: $200-500 depending on traffic and usage patterns.