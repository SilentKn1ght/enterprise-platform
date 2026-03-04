#!/bin/bash

# Pre-Load Test Checklist & Status Dashboard
# Verifies all prerequisites before running load test

set -e

CLUSTER="enterprise-platform-dev-cluster"
SERVICE="enterprise-platform-dev-service"
AWS_REGION="eu-north-1"
ALB_DNS="enterprise-platform-alb-1240013568.eu-north-1.elb.amazonaws.com"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_status() {
    local check_name=$1
    local result=$2
    
    if [[ "$result" == "✓" ]]; then
        echo -e "${GREEN}✓${NC} ${check_name}"
        return 0
    else
        echo -e "${RED}✗${NC} ${check_name}: ${result}"
        return 1
    fi
}

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  LOAD TEST PRE-FLIGHT CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# 1. Check AWS Credentials
echo -e "${YELLOW}1. AWS Credentials${NC}"
if aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
    account=$(aws sts get-caller-identity --query Account --output text)
    user=$(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')
    check_status "AWS Authentication" "✓"
    echo "   Account: $account"
    echo "   User: $user"
else
    check_status "AWS Authentication" "Failed"
    exit 1
fi
echo ""

# 2. Check Tools
echo -e "${YELLOW}2. Required Tools${NC}"
which k6 &>/dev/null && check_status "k6 installed" "✓" || check_status "k6 installed" "Not found"
which aws &>/dev/null && check_status "AWS CLI installed" "✓" || check_status "AWS CLI installed" "Not found"
which curl &>/dev/null && check_status "curl installed" "✓" || check_status "curl installed" "Not found"
echo ""

# 3. Check ECS Resources
echo -e "${YELLOW}3. ECS Resources${NC}"

# Check cluster exists
if aws ecs describe-clusters --clusters "$CLUSTER" --region "$AWS_REGION" --query 'clusters[0].status' --output text &>/dev/null; then
    status=$(aws ecs describe-clusters --clusters "$CLUSTER" --region "$AWS_REGION" --query 'clusters[0].status' --output text)
    check_status "ECS Cluster exists ($CLUSTER)" "✓"
    echo "   Status: $status"
else
    check_status "ECS Cluster exists ($CLUSTER)" "Not found"
fi

# Check service exists
if aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" &>/dev/null; then
    service_status=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" --query 'services[0].status' --output text)
    running=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" --query 'services[0].runningCount' --output text)
    desired=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" --query 'services[0].desiredCount' --output text)
    
    check_status "ECS Service exists ($SERVICE)" "✓"
    echo "   Status: $service_status"
    echo "   Running: $running / Desired: $desired"
else
    check_status "ECS Service exists ($SERVICE)" "Not found"
fi
echo ""

# 4. Check ALB/Health Endpoint
echo -e "${YELLOW}4. Application Health${NC}"

# Check ALB
if nslookup "$ALB_DNS" &>/dev/null; then
    check_status "ALB DNS resolves" "✓"
    alb_ip=$(nslookup "$ALB_DNS" | grep -A1 Name | tail -1 | awk '{print $2}')
    echo "   IP: $alb_ip"
else
    check_status "ALB DNS resolves" "Cannot resolve"
fi

# Check application health endpoint
if curl -s -m 5 "http://$ALB_DNS/health" &>/dev/null; then
    health_code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "http://$ALB_DNS/health")
    if [[ "$health_code" == "200" ]]; then
        check_status "Health endpoint responsive" "✓"
    else
        check_status "Health endpoint responsive" "HTTP $health_code"
    fi
else
    check_status "Health endpoint responsive" "Timeout or unreachable"
fi
echo ""

# 5. Check Auto Scaling Configuration
echo -e "${YELLOW}5. Auto Scaling Configuration${NC}"

# Find ASG
asg_name=$(aws autoscaling describe-auto-scaling-groups \
    --region "$AWS_REGION" \
    --query "AutoScalingGroups[?Tags[?Key=='ECSCluster' && Value=='${CLUSTER}']].AutoScalingGroupName" \
    --output text)

if [[ -n "$asg_name" ]]; then
    asg_info=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --region "$AWS_REGION" \
        --query 'AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity,length(Instances)]' \
        --output text)
    
    read min_size max_size desired_count instance_count <<< "$asg_info"
    
    check_status "Auto Scaling Group found" "✓"
    echo "   Name: $asg_name"
    echo "   Min: $min_size, Max: $max_size, Desired: $desired_count"
    echo "   Running Instances: $instance_count"
    
    # Check scaling policies
    policies=$(aws autoscaling describe-policies \
        --auto-scaling-group-name "$asg_name" \
        --region "$AWS_REGION" \
        --query 'ScalingPolicies[*].PolicyName' \
        --output text)
    
    if [[ -n "$policies" ]]; then
        check_status "Scaling policies configured" "✓"
        echo "   Policies: $policies"
    else
        check_status "Scaling policies configured" "None found"
    fi
else
    check_status "Auto Scaling Group found" "Not found"
fi
echo ""

# 6. Check CloudWatch Alarms
echo -e "${YELLOW}6. CloudWatch Monitoring${NC}"

alarms=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "$CLUSTER" \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[*].AlarmName' \
    --output text)

if [[ -n "$alarms" ]]; then
    alarm_count=$(echo "$alarms" | wc -w)
    check_status "CloudWatch alarms configured" "✓"
    echo "   Found $alarm_count alarms"
else
    check_status "CloudWatch alarms configured" "None"
fi

# Check metrics available
cpu_metric=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$SERVICE" \
    --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 300 \
    --statistics Average \
    --region "$AWS_REGION" \
    --query 'Datapoints' \
    --output text 2>/dev/null)

if [[ -n "$cpu_metric" ]]; then
    check_status "CloudWatch metrics available" "✓"
else
    check_status "CloudWatch metrics available" "Warmup period"
fi
echo ""

# 7. Check Script Files
echo -e "${YELLOW}7. Load Test Scripts${NC}"

test -f "scripts/load-test-with-monitoring.sh" && check_status "load-test-with-monitoring.sh" "✓" || check_status "load-test-with-monitoring.sh" "Not found"
test -f "scripts/monitor-ecs-live.sh" && check_status "monitor-ecs-live.sh" "✓" || check_status "monitor-ecs-live.sh" "Not found"
test -f "scripts/load-test-k6.js" && check_status "load-test-k6.js" "✓" || check_status "load-test-k6.js" "Not found"
test -f "docs/Load-Testing-Guide.md" && check_status "Load-Testing-Guide.md" "✓" || check_status "Load-Testing-Guide.md" "Not found"
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}System is ready for load testing!${NC}"
echo ""
echo -e "${YELLOW}Quick Start:${NC}"
echo "1. Open two terminals"
echo "2. Terminal 1: bash scripts/load-test-with-monitoring.sh"
echo "3. Terminal 2: bash scripts/monitor-ecs-live.sh"
echo ""
echo -e "${YELLOW}Expected Timeline:${NC}"
echo "• 0-2 min:   Ramp up (watch CPU increase)"
echo "• 2-5 min:   Scale out begins (Pending tasks appear)"
echo "• 5-10 min:  Peak load (max task count reached)"
echo "• 10-15 min: Ramp down (observe scale-in)"
echo "• 15-17 min: Cool down (back to baseline)"
echo ""
echo -e "${YELLOW}Monitoring URLs:${NC}"
echo "• Application: http://$ALB_DNS/health"
echo "• CloudWatch: https://console.aws.amazon.com/cloudwatch/"
echo "• ECS: https://console.aws.amazon.com/ecs/"
echo ""
