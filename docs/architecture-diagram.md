# Architecture Diagram

## Multi-Region Resilient Web Application Architecture

```
                                    ┌─────────────────┐
                                    │   CloudFront    │
                                    │   Global CDN    │
                                    └─────────┬───────┘
                                              │
                                    ┌─────────▼───────┐
                                    │    Route 53     │
                                    │  DNS Failover   │
                                    └─────────┬───────┘
                                              │
                        ┌─────────────────────┼─────────────────────┐
                        │                     │                     │
                        ▼                     │                     ▼
            ┌───────────────────────┐         │         ┌───────────────────────┐
            │    PRIMARY REGION     │         │         │   SECONDARY REGION    │
            │     (us-east-1)       │         │         │     (us-west-2)       │
            └───────────────────────┘         │         └───────────────────────┘
                        │                     │                     │
            ┌───────────▼───────────┐         │         ┌───────────▼───────────┐
            │  Application Load     │         │         │  Application Load     │
            │     Balancer          │         │         │     Balancer          │
            └───────────┬───────────┘         │         └───────────┬───────────┘
                        │                     │                     │
        ┌───────────────┼───────────────┐     │     ┌───────────────┼───────────────┐
        │               │               │     │     │               │               │
        ▼               ▼               ▼     │     ▼               ▼               ▼
    ┌───────┐       ┌───────┐       ┌───────┐ │ ┌───────┐       ┌───────┐       ┌───────┐
    │  AZ-A │       │  AZ-B │       │  AZ-C │ │ │  AZ-A │       │  AZ-B │       │  AZ-C │
    │       │       │       │       │       │ │ │       │       │       │       │       │
    │ ECS   │       │ ECS   │       │ ECS   │ │ │ ECS   │       │ ECS   │       │ ECS   │
    │Fargate│       │Fargate│       │Fargate│ │ │Fargate│       │Fargate│       │Fargate│
    └───┬───┘       └───┬───┘       └───┬───┘ │ └───┬───┘       └───┬───┘       └───┬───┘
        │               │               │     │     │               │               │
        └───────────────┼───────────────┘     │     └───────────────┼───────────────┘
                        │                     │                     │
            ┌───────────▼───────────┐         │         ┌───────────▼───────────┐
            │    Aurora Global      │         │         │    Aurora Global      │
            │   Database Cluster    │◄────────┼────────►│   Database Cluster    │
            │     (Primary)         │         │         │    (Secondary)        │
            └───────────────────────┘         │         └───────────────────────┘
                        │                     │                     │
            ┌───────────▼───────────┐         │         ┌───────────▼───────────┐
            │      S3 Bucket        │         │         │      S3 Bucket        │
            │   (Static Assets)     │◄────────┼────────►│   (Static Assets)     │
            │   Cross-Region Repl   │         │         │   Cross-Region Repl   │
            └───────────────────────┘         │         └───────────────────────┘
                        │                     │                     │
            ┌───────────▼───────────┐         │         ┌───────────▼───────────┐
            │     CloudWatch        │         │         │     CloudWatch        │
            │    Monitoring &       │         │         │    Monitoring &       │
            │      Alerting         │         │         │      Alerting         │
            └───────────────────────┘         │         └───────────────────────┘
                                              │
                                    ┌─────────▼───────┐
                                    │       SNS       │
                                    │   Notifications │
                                    └─────────────────┘
```

## Component Details

### Global Layer
- CloudFront: Global CDN with edge locations worldwide
- Route 53: DNS service with health checks and failover routing
- SNS: Cross-region notification service

### Regional Components (Both Regions)

#### Networking
```
VPC (10.0.0.0/16 Primary, 10.1.0.0/16 Secondary)
├── Public Subnets (3 AZs)
│   ├── 10.x.0.0/24 (AZ-A)
│   ├── 10.x.1.0/24 (AZ-B)
│   └── 10.x.2.0/24 (AZ-C)
├── Private Subnets (3 AZs)
│   ├── 10.x.10.0/24 (AZ-A)
│   ├── 10.x.11.0/24 (AZ-B)
│   └── 10.x.12.0/24 (AZ-C)
└── Database Subnets (3 AZs)
    ├── 10.x.20.0/24 (AZ-A)
    ├── 10.x.21.0/24 (AZ-B)
    └── 10.x.22.0/24 (AZ-C)
```

#### Compute Layer
```
Application Load Balancer
├── Target Group (Health Check: /health)
└── ECS Fargate Service
    ├── Task Definition (FastAPI App)
    ├── Auto Scaling (2-10 tasks)
    └── Service Discovery
```

#### Data Layer
```
Aurora Global Database
├── Primary Cluster (us-east-1)
│   ├── Writer Instance (db.r5.large)
│   └── Reader Instance (db.r5.large)
└── Secondary Cluster (us-west-2)
    ├── Writer Instance (db.r5.large)
    └── Reader Instance (db.r5.large)

S3 Cross-Region Replication
├── Primary Bucket (us-east-1)
└── Secondary Bucket (us-west-2)
```

## Traffic Flow Diagrams

### Normal Operations (Primary Active)
```
User Request
    │
    ▼
CloudFront Edge Location
    │
    ▼ (Cache Miss)
Route 53 DNS Resolution
    │
    ▼ (Primary Healthy)
Primary Region ALB
    │
    ▼
ECS Fargate Tasks (us-east-1)
    │
    ▼
Aurora Primary Cluster
    │
    ▼
Response to User
```

### Failover Scenario (Primary Failed)
```
User Request
    │
    ▼
CloudFront Edge Location
    │
    ▼ (Cache Miss)
Route 53 DNS Resolution
    │
    ▼ (Primary Unhealthy)
Secondary Region ALB
    │
    ▼
ECS Fargate Tasks (us-west-2)
    │
    ▼
Aurora Secondary Cluster (Promoted)
    │
    ▼
Response to User
```

## Security Architecture

### Network Security
```
Internet Gateway
    │
    ▼
Public Subnets (ALB Only)
    │
    ▼ (Security Groups)
Private Subnets (ECS Tasks)
    │
    ▼ (Security Groups)
Database Subnets (Aurora)
    │
    ▼
NAT Gateway (Outbound Only)
```

### Security Groups
```
ALB Security Group
├── Inbound: 80/443 from 0.0.0.0/0
└── Outbound: 8000 to ECS Security Group

ECS Security Group
├── Inbound: 8000 from ALB Security Group
└── Outbound: 3306 to RDS Security Group

RDS Security Group
├── Inbound: 3306 from ECS Security Group
└── Outbound: None
```

## Monitoring Architecture

### CloudWatch Metrics Flow
```
Application Metrics
    │
    ▼
CloudWatch Logs
    │
    ▼
CloudWatch Alarms
    │
    ▼ (Threshold Breach)
SNS Topic
    │
    ▼
Email/SMS Notifications
```

### Health Check Flow
```
Route 53 Health Checks
    │
    ├── Primary ALB Health Check
    │   └── GET /health every 30s
    │
    └── Secondary ALB Health Check
        └── GET /health every 30s
    │
    ▼ (Failure Detection)
DNS Failover Triggered
```

## Disaster Recovery Architecture

### RTO/RPO Targets
- RTO (Recovery Time Objective): < 5 minutes
- RPO (Recovery Point Objective): < 1 second

### Failover Components
```
Primary Region Failure
    │
    ▼
Route 53 Health Check Failure (90s)
    │
    ▼
DNS Failover to Secondary (60s)
    │
    ▼
Aurora Global Database Promotion (60s)
    │
    ▼
Application Serving from Secondary (30s)
    │
    ▼
Total RTO: ~4 minutes
```

## Scaling Architecture

### Horizontal Scaling
```
CloudWatch Metrics
    │ (CPU > 70%)
    ▼
ECS Auto Scaling
    │
    ├── Scale Out (Add Tasks)
    └── Scale In (Remove Tasks)
    │
    ▼
ALB Target Registration
```

### Database Scaling
```
Read Traffic Increase
    │
    ▼
Aurora Read Replicas
    │
    ├── Auto Scaling Read Replicas
    └── Connection Load Balancing
```

## Cost Optimization Architecture

### Resource Efficiency
```
ECS Fargate
├── Pay per vCPU/Memory used
├── No idle EC2 instances
└── Automatic scaling

Aurora Serverless v2
├── Pay per ACU consumed
├── Automatic scaling
└── Pause when idle

S3 Intelligent Tiering
├── Automatic tier transitions
├── Cost optimization
└── No retrieval fees
```

This architecture provides:
- 99.99% availability through multi-AZ deployment
- 99.9% availability through multi-region failover
- Sub-second RPO with Aurora Global Database
- Sub-5-minute RTO with automated failover
- Global performance with CloudFront CDN
- Cost optimization through serverless and auto-scaling components