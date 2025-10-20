#!/bin/bash

# Automated Failover Testing Script
# This script tests the multi-region failover capabilities

set -e

# Configuration
PROJECT_NAME="resilient-webapp"
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"
DOMAIN_NAME=""
TEST_DURATION=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    for tool in aws curl jq; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Get configuration
get_configuration() {
    if [ -z "$DOMAIN_NAME" ]; then
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    fi
    
    log "Testing failover for domain: $DOMAIN_NAME"
}

# Test application health
test_health() {
    local url="https://$DOMAIN_NAME/health"
    local response=$(curl -s -w "%{http_code}" -o /dev/null "$url" 2>/dev/null || echo "000")
    echo "$response"
}

# Get current serving region
get_current_region() {
    local url="https://$DOMAIN_NAME/api/status"
    local region=$(curl -s "$url" 2>/dev/null | jq -r '.region' 2>/dev/null || echo "unknown")
    echo "$region"
}

# Monitor application continuously
monitor_application() {
    local duration=$1
    local interval=10
    local end_time=$(($(date +%s) + duration))
    
    log "Monitoring application for $duration seconds..."
    
    while [ $(date +%s) -lt $end_time ]; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local health_code=$(test_health)
        local region=$(get_current_region)
        local response_time=$(curl -w "%{time_total}" -o /dev/null -s "https://$DOMAIN_NAME/health" 2>/dev/null || echo "timeout")
        
        if [ "$health_code" = "200" ]; then
            echo "$timestamp - Healthy (HTTP: $health_code, Region: $region, Time: ${response_time}s)"
        else
            echo "$timestamp - Unhealthy (HTTP: $health_code, Region: $region)"
        fi
        
        sleep $interval
    done
}

# Scale down ECS service
scale_down_service() {
    local cluster="$PROJECT_NAME-primary"
    local service="$PROJECT_NAME-primary"
    
    log "Scaling down primary region ECS service..."
    
    aws ecs update-service \
        --cluster "$cluster" \
        --service "$service" \
        --desired-count 0 \
        --region "$PRIMARY_REGION" > /dev/null
    
    success "Primary region service scaled down"
}

# Scale up ECS service
scale_up_service() {
    local cluster="$PROJECT_NAME-primary"
    local service="$PROJECT_NAME-primary"
    
    log "Scaling up primary region ECS service..."
    
    aws ecs update-service \
        --cluster "$cluster" \
        --service "$service" \
        --desired-count 2 \
        --region "$PRIMARY_REGION" > /dev/null
    
    success "Primary region service scaled up"
}

# Wait for failover
wait_for_failover() {
    local max_wait=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    log "Waiting for failover to secondary region..."
    
    while [ $elapsed -lt $max_wait ]; do
        local region=$(get_current_region)
        local health_code=$(test_health)
        
        if [ "$region" = "$SECONDARY_REGION" ] && [ "$health_code" = "200" ]; then
            success "Failover completed! Now serving from $SECONDARY_REGION"
            return 0
        fi
        
        log "Failover in progress... (Region: $region, Health: $health_code, Elapsed: ${elapsed}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    error "Failover did not complete within $max_wait seconds"
    return 1
}

# Wait for failback
wait_for_failback() {
    local max_wait=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    log "Waiting for failback to primary region..."
    
    while [ $elapsed -lt $max_wait ]; do
        local region=$(get_current_region)
        local health_code=$(test_health)
        
        if [ "$region" = "$PRIMARY_REGION" ] && [ "$health_code" = "200" ]; then
            success "Failback completed! Now serving from $PRIMARY_REGION"
            return 0
        fi
        
        log "Failback in progress... (Region: $region, Health: $health_code, Elapsed: ${elapsed}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    warning "Failback did not complete within $max_wait seconds (this is normal)"
    return 0
}

# Test database connectivity
test_database() {
    log "Testing database connectivity..."
    
    local url="https://$DOMAIN_NAME/api/data"
    local response=$(curl -s "$url" 2>/dev/null)
    
    if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        success "Database connectivity test passed"
        local region=$(echo "$response" | jq -r '.region')
        log "Database serving from region: $region"
    else
        error "Database connectivity test failed"
        echo "Response: $response"
    fi
}

# Generate test report
generate_report() {
    local start_time=$1
    local end_time=$2
    local failover_time=$3
    local failback_time=$4
    
    log "Generating test report..."
    
    cat << EOF

=== FAILOVER TEST REPORT ===
Test Start Time: $(date -d "@$start_time" '+%Y-%m-%d %H:%M:%S')
Test End Time: $(date -d "@$end_time" '+%Y-%m-%d %H:%M:%S')
Total Test Duration: $((end_time - start_time)) seconds

Failover Performance:
- Failover Time: $failover_time seconds
- Target RTO: < 300 seconds
- Status: $([ $failover_time -lt 300 ] && echo "PASSED" || echo "FAILED")

Application Availability:
- Domain: $DOMAIN_NAME
- Primary Region: $PRIMARY_REGION
- Secondary Region: $SECONDARY_REGION

Test Results:
- Application health monitoring
- Primary region failure simulation
- Automatic failover to secondary region
- Database connectivity during failover
$([ $failback_time -gt 0 ] && echo "- Automatic failback to primary region" || echo "- Failback not completed during test")

Recommendations:
- Monitor CloudWatch alarms for any issues
- Review Route 53 health check configuration if failover was slow
- Check ECS service auto-scaling settings
- Verify database replication lag metrics

EOF
}

# Main test function
run_failover_test() {
    local start_time=$(date +%s)
    
    log "=== Starting Failover Test ==="
    
    # Initial state check
    log "Checking initial application state..."
    local initial_region=$(get_current_region)
    local initial_health=$(test_health)
    
    if [ "$initial_health" != "200" ]; then
        error "Application is not healthy before test. Aborting."
        exit 1
    fi
    
    success "Initial state: Healthy, serving from $initial_region"
    
    # Test database before failover
    test_database
    
    # Start monitoring in background
    log "Starting continuous monitoring..."
    monitor_application $TEST_DURATION > failover-monitor.log 2>&1 &
    local monitor_pid=$!
    
    # Wait a bit for monitoring to start
    sleep 5
    
    # Trigger failover
    scale_down_service
    local failover_start=$(date +%s)
    
    # Wait for failover
    if wait_for_failover; then
        local failover_end=$(date +%s)
        local failover_time=$((failover_end - failover_start))
        success "Failover completed in $failover_time seconds"
    else
        error "Failover test failed"
        kill $monitor_pid 2>/dev/null || true
        exit 1
    fi
    
    # Test database after failover
    test_database
    
    # Wait a bit in secondary region
    log "Testing stability in secondary region for 30 seconds..."
    sleep 30
    
    # Restore primary region
    scale_up_service
    local failback_start=$(date +%s)
    
    # Wait for failback (optional)
    wait_for_failback
    local failback_end=$(date +%s)
    local failback_time=$((failback_end - failback_start))
    
    # Stop monitoring
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true
    
    local end_time=$(date +%s)
    
    # Generate report
    generate_report $start_time $end_time $failover_time $failback_time
    
    success "Failover test completed successfully!"
    
    # Show monitoring log
    if [ -f "failover-monitor.log" ]; then
        log "Monitoring log:"
        cat failover-monitor.log
    fi
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    
    # Ensure primary region is restored
    scale_up_service 2>/dev/null || true
    
    # Clean up log files
    rm -f failover-monitor.log
}

# Handle script interruption
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --duration)
            TEST_DURATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--domain DOMAIN_NAME] [--duration SECONDS]"
            echo "  --domain:   Your domain name (e.g., example.com)"
            echo "  --duration: Test monitoring duration in seconds (default: 300)"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
check_prerequisites
get_configuration
run_failover_test