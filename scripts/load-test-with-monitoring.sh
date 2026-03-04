#!/bin/bash

# Load Testing with ECS Scaling Monitoring
set -e

ALB_DNS="enterprise-platform-alb-1240013568.eu-north-1.elb.amazonaws.com"
CLUSTER="enterprise-platform-dev-cluster"
SERVICE="enterprise-platform-dev-service"
AWS_REGION="eu-north-1"
ENDPOINT="http://${ALB_DNS}/health"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ECS Load Test + Scaling Monitoring${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Target URL: ${ENDPOINT}"
echo "Cluster: ${CLUSTER}"
echo "Service: ${SERVICE}"
echo "Region: ${AWS_REGION}"
echo ""

# Function to monitor ECS service
monitor_ecs_scaling() {
    local duration=$1
    local interval=5
    local iterations=$((duration / interval))
    
    echo -e "${YELLOW}Monitoring ECS scaling for ${duration} seconds...${NC}"
    echo ""
    echo -e "${BLUE}Time(s) | Task Count | Pending | Running | CPU% | Memory%${NC}"
    echo -e "${BLUE}--------|-----------|---------|---------|------|----------${NC}"
    
    for ((i = 0; i < iterations; i++)); do
        elapsed=$((i * interval))
        
        # Get ECS service details
        service_info=$(aws ecs describe-services \
            --cluster "$CLUSTER" \
            --services "$SERVICE" \
            --region "$AWS_REGION" \
            --query 'services[0].[desiredCount,pendingCount,runningCount]' \
            --output text)
        
        read desired pending running <<< "$service_info"
        
        # Get CloudWatch metrics for CPU and Memory
        end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        start_time=$(date -u -d "30 seconds ago" +%Y-%m-%dT%H:%M:%SZ)
        
        cpu=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ECS \
            --metric-name CPUUtilization \
            --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$SERVICE" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --period 30 \
            --statistics Average \
            --region "$AWS_REGION" \
            --query 'Datapoints[0].Average' \
            --output text 2>/dev/null || echo "N/A")
        
        memory=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ECS \
            --metric-name MemoryUtilization \
            --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$SERVICE" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --period 30 \
            --statistics Average \
            --region "$AWS_REGION" \
            --query 'Datapoints[0].Average' \
            --output text 2>/dev/null || echo "N/A")
        
        # Format metrics
        if [[ "$cpu" != "N/A" ]]; then
            cpu=$(printf "%.1f" "$cpu")
        fi
        if [[ "$memory" != "N/A" ]]; then
            memory=$(printf "%.1f" "$memory")
        fi
        
        printf "%7d | %9d | %7d | %7d | %4s | %8s\n" "$elapsed" "$desired" "$pending" "$running" "$cpu" "$memory"
        
        sleep "$interval"
    done
}

# Function to capture ECS events
capture_ecs_events() {
    local output_file="ecs-scaling-events.log"
    local start_time=$(date -u -d "2 minutes ago" +%Y-%m-%dT%H:%M:%SZ)
    
    echo ""
    echo -e "${YELLOW}ECS Scaling Events:${NC}"
    
    aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$SERVICE" \
        --region "$AWS_REGION" \
        --query 'services[0].events' \
        --output text | head -20
}

# Function to run k6 load test
run_k6_load_test() {
    export ALB_DNS
    
    echo -e "${GREEN}Starting k6 load test...${NC}"
    echo ""
    
    k6 run - <<EOF
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp up to 10 users
    { duration: '3m', target: 10 },   // Stay at 10 users
    { duration: '2m', target: 50 },   // Ramp up to 50 users
    { duration: '3m', target: 50 },   // Stay at 50 (trigger scaling)
    { duration: '2m', target: 100 },  // Spike to 100 users
    { duration: '3m', target: 100 },  // Stay at 100
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],
    http_req_failed: ['rate<0.05'],
  },
};

export default function () {
  const ALB_DNS = __ENV.ALB_DNS;
  let res = http.get(\`http://\${ALB_DNS}/health\`);
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(0.1);
}
EOF
}

# Get initial state
echo -e "${YELLOW}Initial ECS Service State:${NC}"
aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$AWS_REGION" \
    --query 'services[0].[desiredCount,runningCount,pendingCount,status]' \
    --output text | xargs printf "Desired: %s, Running: %s, Pending: %s, Status: %s\n"
echo ""

# Start monitoring in background
monitor_ecs_scaling 900 &
MONITOR_PID=$!

# Run load test
sleep 2
run_k6_load_test

# Wait for monitoring to complete
wait $MONITOR_PID 2>/dev/null || true

# Capture final state and events
echo ""
echo -e "${YELLOW}Final ECS Service State:${NC}"
aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$AWS_REGION" \
    --query 'services[0].[desiredCount,runningCount,pendingCount,status]' \
    --output text | xargs printf "Desired: %s, Running: %s, Pending: %s, Status: %s\n"
echo ""

capture_ecs_events

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Load Test Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Check CloudWatch Dashboard: Application-logs, system-metrics dashboards"
echo "2. Review Prometheus metrics at: http://<prometheus-url>"
echo "3. Check Grafana dashboards for detailed visualization"
echo "4. Review Auto Scaling Group activities in AWS Console"
