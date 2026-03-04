#!/bin/bash

# Real-time ECS Scaling Monitor
# This script displays live metrics during the load test

CLUSTER="enterprise-platform-dev-cluster"
SERVICE="enterprise-platform-dev-service"
AWS_REGION="eu-north-1"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear

while true; do
    clear
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         ECS AUTOSCALING REAL-TIME MONITOR                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get service info
    service_data=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$SERVICE" \
        --region "$AWS_REGION" \
        --query 'services[0].[desiredCount,runningCount,pendingCount,status,deployments[0].taskDefinition]' \
        --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: Could not connect to AWS. Check credentials and region.${NC}"
        sleep 5
        continue
    fi
    
    desired=$(echo "$service_data" | jq -r '.[0]')
    running=$(echo "$service_data" | jq -r '.[1]')
    pending=$(echo "$service_data" | jq -r '.[2]')
    status=$(echo "$service_data" | jq -r '.[3]')
    task_def=$(echo "$service_data" | jq -r '.[4]' | awk -F'/' '{print $NF}')
    
    # Get Auto Scaling Group info
    asg_data=$(aws autoscaling describe-auto-scaling-groups \
        --region "$AWS_REGION" \
        --query "AutoScalingGroups[?Tags[?Key=='ECSCluster' && Value=='${CLUSTER}']].{DesiredCapacity:DesiredCapacity,MinSize:MinSize,MaxSize:MaxSize,Instances:length(Instances)}" \
        --output json 2>/dev/null | jq '.[0]')
    
    asg_desired=$(echo "$asg_data" | jq -r '.DesiredCapacity // "N/A"')
    asg_min=$(echo "$asg_data" | jq -r '.MinSize // "N/A"')
    asg_max=$(echo "$asg_data" | jq -r '.MaxSize // "N/A"')
    asg_instances=$(echo "$asg_data" | jq -r '.Instances // "N/A"')
    
    # Status color
    if [[ "$status" == "ACTIVE" ]]; then
        status_color="${GREEN}${status}${NC}"
    else
        status_color="${YELLOW}${status}${NC}"
    fi
    
    # Task status
    tasks_color="${GREEN}"
    if [[ "$pending" -gt 0 ]]; then
        tasks_color="${YELLOW}"
    fi
    
    echo -e "${BLUE}SERVICE INFORMATION:${NC}"
    echo -e "  Status: $status_color"
    echo -e "  Task Definition: ${BLUE}${task_def}${NC}"
    echo ""
    
    echo -e "${BLUE}ECS TASK COUNTS:${NC}"
    echo -e "  Desired:  ${BLUE}${desired}${NC} tasks"
    echo -e "  Running:  ${tasks_color}${running}${NC} tasks"
    echo -e "  Pending:  ${YELLOW}${pending}${NC} tasks (starting)"
    echo ""
    
    echo -e "${BLUE}AUTOSCALING GROUP (EC2):${NC}"
    echo -e "  Desired:  ${BLUE}${asg_desired}${NC} instances"
    echo -e "  Min:      ${asg_min}, Max: ${asg_max}"
    echo -e "  Running:  ${GREEN}${asg_instances}${NC} instances"
    echo ""
    
    # Get CloudWatch Metrics (last 5 minutes average)
    end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    start_time=$(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%SZ)
    
    echo -e "${BLUE}PERFORMANCE METRICS (Last 5 min avg):${NC}"
    
    cpu=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ECS \
        --metric-name CPUUtilization \
        --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$SERVICE" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    memory=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ECS \
        --metric-name MemoryUtilization \
        --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$SERVICE" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ "$cpu" != "None" && "$cpu" != "" ]]; then
        cpu_fmt=$(printf "%.1f" "$cpu")
        if (( $(echo "$cpu > 80" | bc -l) )); then
            cpu_color="${RED}"
        elif (( $(echo "$cpu > 50" | bc -l) )); then
            cpu_color="${YELLOW}"
        else
            cpu_color="${GREEN}"
        fi
        echo -e "  CPU: ${cpu_color}${cpu_fmt}%${NC}"
    else
        echo -e "  CPU: ${YELLOW}N/A (warmup)${NC}"
    fi
    
    if [[ "$memory" != "None" && "$memory" != "" ]]; then
        mem_fmt=$(printf "%.1f" "$memory")
        if (( $(echo "$memory > 80" | bc -l) )); then
            mem_color="${RED}"
        elif (( $(echo "$memory > 50" | bc -l) )); then
            mem_color="${YELLOW}"
        else
            mem_color="${GREEN}"
        fi
        echo -e "  Memory: ${mem_color}${mem_fmt}%${NC}"
    else
        echo -e "  Memory: ${YELLOW}N/A (warmup)${NC}"
    fi
    
    echo ""
    
    # Recent scaling activity
    echo -e "${BLUE}RECENT SCALING ACTIVITY:${NC}"
    scaling_activity=$(aws autoscaling describe-scaling-activities \
        --auto-scaling-group-name "${CLUSTER}-asg" \
        --max-records 3 \
        --region "$AWS_REGION" \
        --query 'Activities[0].[StartTime,Description,StatusCode]' \
        --output text 2>/dev/null)
    
    if [[ -n "$scaling_activity" ]]; then
        echo "$scaling_activity" | while read -r timestamp description status; do
            echo "  $timestamp - $status"
            echo "    $description" | head -c 60
            echo ""
        done
    else
        echo "  ${YELLOW}No recent scaling activity${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo "Refreshing in 5 seconds... (Press Ctrl+C to exit)"
    echo ""
    
    # Get current time
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "Last updated: ${BLUE}${current_time}${NC}"
    
    sleep 5
done
