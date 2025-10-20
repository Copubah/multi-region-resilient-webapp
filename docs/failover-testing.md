# Failover Testing Guide

This guide provides comprehensive procedures to test the multi-region failover capabilities of your resilient web application.

## Prerequisites

Before starting failover tests, ensure:
- Both primary and secondary regions are fully deployed
- Route 53 health checks are configured and passing
- CloudWatch monitoring is active
- SNS notifications are configured
- You have appropriate AWS permissions

## Test Scenarios

### 1. Application-Level Failover Test

#### Objective
Test automatic failover when the application becomes unhealthy in the primary region.

#### Steps
1. Baseline Check
   ```bash
   # Check current DNS resolution
   nslookup your-domain.com
   
   # Test application health
   curl -I https://your-domain.com/health
   ```

2. Simulate Application Failure
   ```bash
   # Scale down ECS service in primary region
   aws ecs update-service \
     --cluster resilient-webapp-primary \
     --service resilient-webapp-primary \
     --desired-count 0 \
     --region us-east-1
   ```

3. Monitor Failover Process
   ```bash
   # Watch Route 53 health check status
   aws route53 get-health-check \
     --health-check-id YOUR_HEALTH_CHECK_ID
   
   # Monitor DNS resolution changes
   watch -n 10 'nslookup your-domain.com'
   ```

4. Verify Secondary Region Activation
   ```bash
   # Test application from secondary region
   curl -I https://your-domain.com/health
   
   # Check response headers for region information
   curl -s https://your-domain.com/api/status | jq '.region'
   ```

5. Restore Primary Region
   ```bash
   # Scale up ECS service in primary region
   aws ecs update-service \
     --cluster resilient-webapp-primary \
     --service resilient-webapp-primary \
     --desired-count 2 \
     --region us-east-1
   ```

#### Expected Results
- Health check failure detected within 90 seconds
- DNS failover completed within 2-3 minutes
- Application accessible from secondary region
- Automatic failback when primary region recovers

### 2. Database Failover Test

#### Objective
Test Aurora Global Database failover capabilities.

#### Steps
1. Check Current Database Status
   ```bash
   # Check primary cluster status
   aws rds describe-db-clusters \
     --db-cluster-identifier resilient-webapp-primary-cluster \
     --region us-east-1
   
   # Check secondary cluster status
   aws rds describe-db-clusters \
     --db-cluster-identifier resilient-webapp-secondary-cluster \
     --region us-west-2
   ```

2. Simulate Database Failure
   ```bash
   # Failover Aurora Global Database
   aws rds failover-global-cluster \
     --global-cluster-identifier resilient-webapp-global-cluster \
     --target-db-cluster-identifier resilient-webapp-secondary-cluster \
     --region us-west-2
   ```

3. Monitor Failover Progress
   ```bash
   # Watch cluster status
   watch -n 30 'aws rds describe-db-clusters \
     --db-cluster-identifier resilient-webapp-secondary-cluster \
     --region us-west-2 | jq ".DBClusters[0].Status"'
   ```

4. Test Application Database Connectivity
   ```bash
   # Test database operations
   curl -s https://your-domain.com/api/data | jq '.'
   ```

#### Expected Results
- Database failover completes within 1-2 minutes
- Application maintains database connectivity
- Data consistency preserved across regions
- Minimal data loss (RPO < 1 second)

### 3. Complete Region Failure Test

#### Objective
Test complete regional failure scenario.

#### Steps
1. Document Current State
   ```bash
   # Record current endpoints and status
   aws elbv2 describe-load-balancers \
     --region us-east-1 | jq '.LoadBalancers[].DNSName'
   
   aws route53 list-resource-record-sets \
     --hosted-zone-id YOUR_HOSTED_ZONE_ID
   ```

2. Simulate Complete Region Failure
   ```bash
   # Stop all ECS services in primary region
   aws ecs update-service \
     --cluster resilient-webapp-primary \
     --service resilient-webapp-primary \
     --desired-count 0 \
     --region us-east-1
   
   # Simulate ALB failure by modifying security groups
   aws ec2 revoke-security-group-ingress \
     --group-id YOUR_ALB_SECURITY_GROUP_ID \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0 \
     --region us-east-1
   ```

3. Monitor Complete Failover
   ```bash
   # Monitor health checks
   aws route53 get-health-check \
     --health-check-id YOUR_PRIMARY_HEALTH_CHECK_ID
   
   # Test application availability
   while true; do
     curl -w "%{http_code} - %{time_total}s\n" \
          -o /dev/null -s https://your-domain.com/health
     sleep 10
   done
   ```

4. Verify Secondary Region Operation
   ```bash
   # Test all application endpoints
   curl https://your-domain.com/
   curl https://your-domain.com/api/status
   curl https://your-domain.com/api/data
   
   # Check CloudFront behavior
   curl -I https://your-domain.com/ | grep -i x-cache
   ```

#### Expected Results
- Complete failover within 3-5 minutes
- All application functionality available from secondary region
- CloudFront automatically routes to healthy origin
- Database operations continue without interruption

### 4. Network Partition Test

#### Objective
Test behavior during network connectivity issues.

#### Steps
1. Create Network Partition
   ```bash
   # Modify route tables to simulate network issues
   aws ec2 replace-route \
     --route-table-id YOUR_PRIVATE_ROUTE_TABLE_ID \
     --destination-cidr-block 0.0.0.0/0 \
     --gateway-id YOUR_INTERNET_GATEWAY_ID \
     --region us-east-1
   ```

2. Monitor Application Behavior
   ```bash
   # Check ECS task health
   aws ecs describe-services \
     --cluster resilient-webapp-primary \
     --services resilient-webapp-primary \
     --region us-east-1
   
   # Monitor load balancer targets
   aws elbv2 describe-target-health \
     --target-group-arn YOUR_TARGET_GROUP_ARN \
     --region us-east-1
   ```

#### Expected Results
- Load balancer health checks fail
- ECS tasks marked as unhealthy
- Traffic automatically routed to secondary region
- No data loss during network partition

## Automated Testing Scripts

### Health Check Monitor
```bash
#!/bin/bash
# monitor-health.sh

DOMAIN="your-domain.com"
INTERVAL=10

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    HTTP_CODE=$(curl -w "%{http_code}" -o /dev/null -s "https://$DOMAIN/health")
    RESPONSE_TIME=$(curl -w "%{time_total}" -o /dev/null -s "https://$DOMAIN/health")
    
    echo "$TIMESTAMP - HTTP: $HTTP_CODE - Time: ${RESPONSE_TIME}s"
    
    if [ "$HTTP_CODE" != "200" ]; then
        echo "ALERT: Health check failed!"
    fi
    
    sleep $INTERVAL
done
```

### Failover Test Script
```bash
#!/bin/bash
# test-failover.sh

set -e

DOMAIN="your-domain.com"
PRIMARY_CLUSTER="resilient-webapp-primary"
PRIMARY_SERVICE="resilient-webapp-primary"
PRIMARY_REGION="us-east-1"

echo "Starting failover test..."

# Step 1: Verify initial state
echo "Checking initial state..."
curl -s "https://$DOMAIN/api/status" | jq '.region'

# Step 2: Trigger failover
echo "Triggering failover by scaling down primary region..."
aws ecs update-service \
    --cluster $PRIMARY_CLUSTER \
    --service $PRIMARY_SERVICE \
    --desired-count 0 \
    --region $PRIMARY_REGION

# Step 3: Monitor failover
echo "Monitoring failover progress..."
for i in {1..30}; do
    sleep 10
    REGION=$(curl -s "https://$DOMAIN/api/status" 2>/dev/null | jq -r '.region' || echo "error")
    echo "Attempt $i: Current region: $REGION"
    
    if [ "$REGION" = "us-west-2" ]; then
        echo "Failover successful! Now serving from secondary region."
        break
    fi
done

# Step 4: Restore primary region
echo "Restoring primary region..."
aws ecs update-service \
    --cluster $PRIMARY_CLUSTER \
    --service $PRIMARY_SERVICE \
    --desired-count 2 \
    --region $PRIMARY_REGION

echo "Failover test completed."
```

## Monitoring During Tests

### Key Metrics to Watch
1. Route 53 Health Check Status
   - Health check latency
   - Success/failure rates
   - Geographic distribution

2. Application Performance
   - Response times
   - Error rates
   - Throughput

3. Database Metrics
   - Connection counts
   - Query performance
   - Replication lag

4. Infrastructure Health
   - ECS task status
   - Load balancer health
   - CloudFront cache hit rates

### CloudWatch Dashboards
Create custom dashboards to monitor:
- Cross-region health status
- Failover timing metrics
- Application performance during failover
- Database replication status

## Post-Test Validation

After each test, verify:
1. All services return to normal operation
2. Data consistency across regions
3. No data loss occurred
4. Monitoring alerts functioned correctly
5. Documentation reflects actual behavior

## Troubleshooting Common Issues

### Slow Failover
- Check Route 53 health check intervals
- Verify DNS TTL settings
- Review CloudFront cache behaviors

### Data Inconsistency
- Check Aurora Global Database lag
- Verify application connection strings
- Review transaction isolation levels

### Incomplete Failover
- Verify all health checks are configured
- Check security group rules
- Review IAM permissions for cross-region access

## Best Practices

1. Regular Testing: Perform failover tests monthly
2. Documentation: Keep runbooks updated with actual timings
3. Automation: Automate testing where possible
4. Monitoring: Continuously monitor during tests
5. Communication: Notify stakeholders before testing
6. Rollback Plans: Always have rollback procedures ready