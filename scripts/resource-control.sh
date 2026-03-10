#!/bin/bash

#################################################################################
# Resource Control Script - Manual Start/Stop for Cost Optimization
# Purpose: Manually start and stop ECS services and RDS databases
# Usage: ./scripts/resource-control.sh [start|stop|status|menu]
#################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration from terraform.tfvars
PROJECT_NAME="enterprise-platform"
ENVIRONMENT="dev"
AWS_REGION="eu-north-1"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-cluster"
SERVICE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-service"
GRAFANA_SERVICE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-grafana"
DB_INSTANCE_ID="${PROJECT_NAME}-db"
ALB_NAME="${PROJECT_NAME}-alb"
NAT_TAG_KEY="Name"
NAT_TAG_VALUE="${PROJECT_NAME}-${ENVIRONMENT}-nat"

# Default desired task count when starting
DEFAULT_TASK_COUNT=2

# Cost configuration (in USD per hour, approximate for eu-north-1)
COST_ECS_FARGATE=0.035
COST_RDS_MICRO=0.038
COST_NAT_GATEWAY=0.045
COST_NAT_DATA_PER_GB=0.032
COST_ALB=0.016

#################################################################################
# Helper Functions
#################################################################################

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

confirm() {
    local prompt="$1"
    local response
    
    while true; do
        read -p "$(echo -e ${YELLOW})$prompt (yes/no): $(echo -e ${NC})" response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN])
                return 1
                ;;
            *)
                print_warning "Please answer 'yes' or 'no'"
                ;;
        esac
    done
}

check_aws_credentials() {
    if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
}

#################################################################################
# Status Check Functions
#################################################################################

check_ecs_service_status() {
    print_info "Checking ECS Service status..."
    
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION" \
        --query 'services[0].[serviceName,status,desiredCount,runningCount,pendingCount]' \
        --output table
}

check_grafana_service_status() {
    print_info "Checking Grafana Service status..."
    
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$GRAFANA_SERVICE_NAME" \
        --region "$AWS_REGION" \
        --query 'services[0].[serviceName,status,desiredCount,runningCount,pendingCount]' \
        --output table
}

check_rds_status() {
    print_info "Checking RDS Database status..."
    
    aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass]' \
        --output table
}

check_nat_gateway_status() {
    print_info "Checking NAT Gateway status..."
    
    aws ec2 describe-nat-gateways \
        --filter "Name=tag:$NAT_TAG_KEY,Values=$NAT_TAG_VALUE" \
        --region "$AWS_REGION" \
        --query 'NatGateways[*].[NatGatewayId,State]' \
        --output table || print_warning "Could not retrieve NAT Gateway status"
}

check_alb_status() {
    print_info "Checking Application Load Balancer status..."
    
    aws elbv2 describe-load-balancers \
        --names "$ALB_NAME" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[*].[LoadBalancerName,State.Code]' \
        --output table 2>/dev/null || print_warning "ALB not found or no active ALBs"
}

check_all_resources_status() {
    print_header "CURRENT RESOURCE STATUS"
    
    echo -e "${CYAN}━━━━━━━━━━━━ ECS SERVICE (Main App) ━━━━━━━━━━━━${NC}"
    check_ecs_service_status || print_warning "ECS Service status check failed"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━ GRAFANA SERVICE ━━━━━━━━━━━━${NC}"
    check_grafana_service_status || print_warning "Grafana Service status check failed"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━ RDS DATABASE ━━━━━━━━━━━━${NC}"
    check_rds_status || print_warning "RDS Database status check failed"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━ NAT GATEWAY ━━━━━━━━━━━━${NC}"
    check_nat_gateway_status
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━ LOAD BALANCER ━━━━━━━━━━${NC}"
    check_alb_status
}

estimate_cost_savings() {
    print_header "ESTIMATED COST SAVINGS BREAKDOWN"
    
    echo -e "${CYAN}Hourly Cost Estimates (Approximate, eu-north-1):${NC}"
    echo ""
    echo "  ${CYAN}Scalable Resources (Can be stopped):${NC}"
    echo "    • ECS Fargate (2×256 CPU, 512 MB): \$${COST_ECS_FARGATE}/hour"
    echo "    • RDS db.t3.micro: \$${COST_RDS_MICRO}/hour"
    echo "    ───────────────────────────────"
    echo "    Subtotal (ECS + RDS): \$$(echo "${COST_ECS_FARGATE} + ${COST_RDS_MICRO}" | bc)/hour"
    echo ""
    echo "  ${CYAN}Permanent Infrastructure (Always running):${NC}"
    echo "    • NAT Gateway: \$${COST_NAT_GATEWAY}/hour"
    echo "    • Load Balancer: \$${COST_ALB}/hour"
    echo "    • VPC & Networking: ~\$0.04/month (negligible)"
    echo "    ───────────────────────────────"
    echo "    Subtotal (Fixed): \$$(echo "${COST_NAT_GATEWAY} + ${COST_ALB}" | bc)/hour"
    echo ""
    
    TOTAL_RUNNING=$(echo "${COST_ECS_FARGATE} + ${COST_RDS_MICRO} + ${COST_NAT_GATEWAY} + ${COST_ALB}" | bc)
    SAVINGS_BASIC=$(echo "${COST_ECS_FARGATE} + ${COST_RDS_MICRO}" | bc)
    SAVINGS_AGGRESSIVE=$(echo "${COST_ECS_FARGATE} + ${COST_RDS_MICRO} + ${COST_NAT_GATEWAY} + ${COST_ALB}" | bc)
    
    echo -e "${GREEN}Total running resources: \$$TOTAL_RUNNING/hour${NC}"
    echo ""
    
    echo -e "${YELLOW}Savings Options:${NC}"
    echo ""
    echo "  Option 1: STOP (ECS + RDS only)"
    echo "    • Save: \$$SAVINGS_BASIC/hour (~\$$(echo "$SAVINGS_BASIC * 730" | bc)/month)"
    echo "    • Still running: NAT Gateway + ALB"
    echo "    • Complexity: Low"
    echo "    • Time: ~2 minutes"
    echo ""
    echo "  Option 2: DELETE (NAT Gateway + ALB + Stop ECS + RDS)"
    echo "    • Save: \$$SAVINGS_AGGRESSIVE/hour (~\$$(echo "$SAVINGS_AGGRESSIVE * 730" | bc)/month)"
    echo "    • Stopped: Everything except VPC"
    echo "    • Complexity: Medium"
    echo "    • Time: ~10 minutes (recreation)"
    echo "    • Trade-off: Must recreate NAT and ALB to start"
    echo ""
    echo "  Option 3: SELECTIVE (Delete NAT only)"
    echo "    • Save: \$${COST_NAT_GATEWAY}/hour (~\$$(echo "$COST_NAT_GATEWAY * 730" | bc)/month)"
    echo "    • Complexity: High"
    echo "    • Limitation: Private RDS loses internet access"
    echo ""
    
    echo -e "${CYAN}Recommendations:${NC}"
    echo "  • Daily development: Use Option 1 (stop at end of day)"
    echo "  • Weekend/off-hours: Use Option 2 (delete NAT + ALB)"
    echo "  • Long-term inactive: Use Option 2 (saves most money)"
}

show_cost_details() {
    print_header "DETAILED COST ANALYSIS"
    
    echo -e "${CYAN}NAT Gateway Details:${NC}"
    echo "  • Hourly charge: \$${COST_NAT_GATEWAY}/hour"
    echo "  • Data processing: \$${COST_NAT_DATA_PER_GB}/GB (eastbound data)"
    echo "  • Monthly (idle): ~\$32.85 (0 data transfer)"
    echo "  • Monthly (10GB/day): ~\$62.85"
    echo "  • When active: Process all outbound traffic from private subnets"
    echo "  • Usage: RDS backups, package updates, external API calls"
    echo ""
    echo -e "${CYAN}Application Load Balancer Details:${NC}"
    echo "  • Hourly charge: \$${COST_ALB}/hour"
    echo "  • Monthly (idle): ~\$11.68"
    echo "  • Data processing: \$0.006/LCU (small charge based on traffic)"
    echo "  • When active: Routes traffic to ECS tasks"
    echo "  • Availability: Multi-AZ (increases reliability)"
    echo ""
    echo -e "${CYAN}Impact of Deletions:${NC}"
    echo "  • Delete NAT Gateway: Private RDS loses outbound internet"
    echo "    - Backups still work (internal AWS network)"
    echo "    - Critical for: OS patches, AWS CLI access"
    echo "    - Elastic IP deallocates automatically"
    echo ""
    echo "  • Delete ALB: No load balancing for ECS"
    echo "    - Targets deregister automatically"
    echo "    - DNS name becomes unavailable"
    echo "    - Quick to recreate via Terraform"
    echo ""
}

#################################################################################
# ECS Service Control Functions
#################################################################################

start_ecs_service() {
    print_header "STARTING ECS SERVICE"
    
    check_ecs_service_status
    
    print_info "This will scale up the ECS service to $DEFAULT_TASK_COUNT tasks"
    if ! confirm "Do you want to start the ECS service?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Scaling up ECS service to $DEFAULT_TASK_COUNT tasks..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count "$DEFAULT_TASK_COUNT" \
        --region "$AWS_REGION" \
        --query 'service.[serviceName,desiredCount]' \
        --output table
    
    print_success "ECS service start command sent. Waiting for tasks to start..."
    sleep 5
    check_ecs_service_status
}

stop_ecs_service() {
    print_header "STOPPING ECS SERVICE"
    
    check_ecs_service_status
    
    print_warning "This will scale down the ECS service to 0 tasks and stop all running containers"
    if ! confirm "Do you want to stop the ECS service?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Scaling down ECS service to 0 tasks..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count 0 \
        --region "$AWS_REGION" \
        --query 'service.[serviceName,desiredCount]' \
        --output table
    
    print_success "ECS service stop command sent. Waiting for tasks to stop..."
    sleep 5
    check_ecs_service_status
}

start_grafana_service() {
    print_header "STARTING GRAFANA SERVICE"
    
    check_grafana_service_status
    
    print_info "This will scale up the Grafana service to 1 task"
    if ! confirm "Do you want to start the Grafana service?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Scaling up Grafana service to 1 task..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$GRAFANA_SERVICE_NAME" \
        --desired-count 1 \
        --region "$AWS_REGION" \
        --query 'service.[serviceName,desiredCount]' \
        --output table
    
    print_success "Grafana service start command sent. Waiting for task to start..."
    sleep 5
    check_grafana_service_status
}

stop_grafana_service() {
    print_header "STOPPING GRAFANA SERVICE"
    
    check_grafana_service_status
    
    print_warning "This will scale down the Grafana service to 0 tasks"
    if ! confirm "Do you want to stop the Grafana service?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Scaling down Grafana service to 0 tasks..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$GRAFANA_SERVICE_NAME" \
        --desired-count 0 \
        --region "$AWS_REGION" \
        --query 'service.[serviceName,desiredCount]' \
        --output table
    
    print_success "Grafana service stop command sent. Waiting for task to stop..."
    sleep 5
    check_grafana_service_status
}

#################################################################################
# RDS Database Control Functions
#################################################################################

start_rds_database() {
    print_header "STARTING RDS DATABASE"
    
    check_rds_status
    
    print_info "This will start the RDS database instance"
    if ! confirm "Do you want to start the RDS database?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Starting RDS database..."
    aws rds start-db-instance \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstance.[DBInstanceIdentifier,DBInstanceStatus]' \
        --output table
    
    print_success "RDS database start command sent. This may take 1-2 minutes..."
    print_info "Waiting 10 seconds before checking status..."
    sleep 10
    check_rds_status
}

stop_rds_database() {
    print_header "STOPPING RDS DATABASE"
    
    check_rds_status
    
    print_warning "This will stop the RDS database instance. Applications will lose connection."
    if ! confirm "Do you want to stop the RDS database?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Stopping RDS database..."
    aws rds stop-db-instance \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstance.[DBInstanceIdentifier,DBInstanceStatus]' \
        --output table
    
    print_success "RDS database stop command sent. Waiting for confirmation..."
    sleep 5
    check_rds_status
}

#################################################################################
# Combined Control Functions
#################################################################################

start_all_resources() {
    print_header "STARTING ALL RESOURCES"
    
    print_warning "This will start ECS service, Grafana, and RDS database"
    if ! confirm "Do you want to start all resources?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Starting RDS database first (takes 1-2 minutes)..."
    start_rds_database
    
    echo ""
    print_info "Waiting 30 seconds for database to stabilize..."
    sleep 30
    
    echo ""
    print_info "Starting main ECS service..."
    start_ecs_service
    
    echo ""
    print_info "Starting Grafana service..."
    start_grafana_service
    
    print_success "All resources started!"
    estimate_cost_savings
}

stop_all_resources() {
    print_header "STOPPING ALL RESOURCES"
    
    print_warning "This will stop ECS service, Grafana, and RDS database"
    if ! confirm "Do you want to stop all resources?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Stopping main ECS service..."
    stop_ecs_service
    
    echo ""
    print_info "Stopping Grafana service..."
    stop_grafana_service
    
    echo ""
    print_info "Stopping RDS database..."
    stop_rds_database
    
    print_success "All resources stopped!"
    estimate_cost_savings
}

#################################################################################
# NAT Gateway Control Functions
#################################################################################

delete_nat_gateway() {
    print_header "DELETE NAT GATEWAY - AGGRESSIVE COST OPTIMIZATION"
    
    check_nat_gateway_status
    
    echo ""
    print_warning "This will DELETE the NAT Gateway and release its Elastic IP"
    echo ""
    echo -e "${RED}⚠  WARNINGS:${NC}"
    echo "  1. Private RDS will lose outbound internet access"
    echo "  2. OS security patches may fail"
    echo "  3. External API calls from RDS will not work"
    echo "  4. Backups still work (internal AWS network)"
    echo "  5. Elastic IP will be deallocated"
    echo "  6. Recreation takes ~3-5 minutes"
    echo ""
    
    if ! confirm "Delete NAT Gateway and save \$${COST_NAT_GATEWAY}/hour?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Finding NAT Gateway..."
    NAT_GATEWAY_ID=$(aws ec2 describe-nat-gateways \
        --filter "Name=tag:$NAT_TAG_KEY,Values=$NAT_TAG_VALUE" \
        --region "$AWS_REGION" \
        --query 'NatGateways[0].NatGatewayId' \
        --output text)
    
    if [ "$NAT_GATEWAY_ID" == "None" ] || [ -z "$NAT_GATEWAY_ID" ]; then
        print_error "NAT Gateway not found"
        return
    fi
    
    print_info "Deleting NAT Gateway: $NAT_GATEWAY_ID"
    aws ec2 delete-nat-gateway \
        --nat-gateway-id "$NAT_GATEWAY_ID" \
        --region "$AWS_REGION"
    
    print_success "NAT Gateway delete initiated. Waiting for completion..."
    sleep 10
    check_nat_gateway_status
    
    print_info "Note: Elastic IP may take a moment to deallocate"
}

recreate_nat_gateway() {
    print_header "RECREATE NAT GATEWAY"
    
    print_info "This will recreate the NAT Gateway for outbound internet access"
    if ! confirm "Recreate NAT Gateway?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Running Terraform to recreate NAT Gateway..."
    cd terraform
    
    print_info "Planning changes..."
    terraform plan -target=module.networking.aws_nat_gateway.main -out=tfplan_nat
    
    print_warning "Review the plan above. This will:"
    echo "  1. Create new Elastic IP"
    echo "  2. Create NAT Gateway"
    echo "  3. Route private traffic through NAT"
    
    if ! confirm "Apply Terraform changes?"; then
        print_warning "Operation cancelled. Run 'rm tfplan_nat' to clean up."
        cd ..
        return
    fi
    
    print_info "Applying Terraform..."
    terraform apply tfplan_nat
    
    print_success "NAT Gateway recreated!"
    cd ..
    sleep 5
    check_nat_gateway_status
}

#################################################################################
# ALB Control Functions
#################################################################################

delete_alb() {
    print_header "DELETE APPLICATION LOAD BALANCER - AGGRESSIVE COST OPTIMIZATION"
    
    check_alb_status
    
    echo ""
    print_warning "This will DELETE the Application Load Balancer"
    echo ""
    echo -e "${RED}⚠  WARNINGS:${NC}"
    echo "  1. External access to application will be unavailable"
    echo "  2. DNS name ${ALB_NAME} will be inaccessible"
    echo "  3. Only do this when ECS service is STOPPED"
    echo "  4. Saves \$${COST_ALB}/hour (~\$11.68/month)"
    echo "  5. Recreation takes ~5 minutes"
    echo ""
    
    # Check if ECS service is running
    RUNNING_COUNT=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION" \
        --query 'services[0].runningCount' \
        --output text)
    
    if [ "$RUNNING_COUNT" -gt 0 ]; then
        print_error "ERROR: ECS service is still running ($RUNNING_COUNT tasks)"
        print_info "Stop the ECS service first before deleting ALB"
        return
    fi
    
    if ! confirm "Delete ALB and save \$${COST_ALB}/hour?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Deleting Application Load Balancer: $ALB_NAME"
    aws elbv2 delete-load-balancer \
        --load-balancer-arn $(aws elbv2 describe-load-balancers \
            --names "$ALB_NAME" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text) \
        --region "$AWS_REGION"
    
    print_success "ALB delete initiated. Waiting for completion..."
    sleep 10
    check_alb_status
}

recreate_alb() {
    print_header "RECREATE APPLICATION LOAD BALANCER"
    
    print_info "This will recreate the ALB for load balancing"
    if ! confirm "Recreate ALB?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    print_info "Running Terraform to recreate ALB..."
    cd terraform
    
    print_info "Planning changes..."
    terraform plan -target=module.alb.aws_lb.main -out=tfplan_alb
    
    print_warning "Review the plan above. This will create:"
    echo "  1. Application Load Balancer"
    echo "  2. Target Group for ECS tasks"
    echo "  3. HTTP Listener (port 80)"
    echo "  4. CloudWatch Alarms"
    
    if ! confirm "Apply Terraform changes?"; then
        print_warning "Operation cancelled. Run 'rm tfplan_alb' to clean up."
        cd ..
        return
    fi
    
    print_info "Applying Terraform..."
    terraform apply tfplan_alb
    
    print_success "ALB recreated!"
    cd ..
    sleep 5
    check_alb_status
}

#################################################################################
# Interactive Menu
#################################################################################

show_menu() {
    print_header "ENTERPRISE PLATFORM - RESOURCE CONTROL"
    
    echo -e "${CYAN}Quick Actions:${NC}"
    echo "  1) Start all resources (App + Grafana + RDS)"
    echo "  2) Stop all resources (App + Grafana + RDS)"
    echo ""
    echo -e "${CYAN}Application Service:${NC}"
    echo "  3) Start main ECS service only"
    echo "  4) Stop main ECS service only"
    echo "  5) Check main ECS service status"
    echo ""
    echo -e "${CYAN}Grafana Service:${NC}"
    echo "  6) Start Grafana service only"
    echo "  7) Stop Grafana service only"
    echo "  8) Check Grafana service status"
    echo ""
    echo -e "${CYAN}RDS Database:${NC}"
    echo "  16) Start RDS database only"
    echo "  17) Stop RDS database only"
    echo "  18) Check RDS status"
    echo ""
    echo -e "${CYAN}Advanced (Infrastructure):${NC}"
    echo "  11) Delete NAT Gateway (save \$${COST_NAT_GATEWAY}/hour)"
    echo "  12) Recreate NAT Gateway"
    echo "  13) Delete Load Balancer (save \$${COST_ALB}/hour)"
    echo "  14) Recreate Load Balancer"
    echo ""
    echo -e "${CYAN}Status & Info:${NC}"
    echo "  9) Check all resources status"
    echo "  10) View cost savings breakdown"
    echo "  15) View detailed cost analysis"
    echo ""
    echo -e "${CYAN}System:${NC}"
    echo "  0) Exit"
    echo ""
}

interactive_menu() {
    while true; do
        show_menu
        
        read -p "$(echo -e ${YELLOW})Select an option [0-15]: $(echo -e ${NC})" choice
        echo ""
        
        case $choice in
            1)  start_all_resources ;;
            2)  stop_all_resources ;;
            3)  start_ecs_service ;;
            4)  stop_ecs_service ;;
            5)  check_ecs_service_status ;;
            6)  start_grafana_service ;;
            7)  stop_grafana_service ;;
            8)  check_grafana_service_status ;;
            9)  check_all_resources_status ;;
            10) estimate_cost_savings ;;
            11) delete_nat_gateway ;;
            12) recreate_nat_gateway ;;
            13) delete_alb ;;
            14) recreate_alb ;;
            15) show_cost_details ;;
            16) start_rds_database ;;
            17) stop_rds_database ;;
            18) check_rds_status ;;
            0)  
                print_info "Exiting..."
                exit 0
                ;;
            *)  
                print_error "Invalid option. Please try again."
                ;;
        esac
        
        echo ""
        read -p "$(echo -e ${YELLOW})Press Enter to continue...$(echo -e ${NC})"
    done
}

#################################################################################
# Main Script Logic
#################################################################################

main() {
    # Check AWS credentials
    check_aws_credentials
    
    # Handle command line arguments
    if [ $# -eq 0 ]; then
        # No arguments - show interactive menu
        interactive_menu
    else
        # Handle direct commands
        case "$1" in
            start|start-all)
                start_all_resources
                ;;
            stop|stop-all)
                stop_all_resources
                ;;
            start-ecs)
                start_ecs_service
                ;;
            stop-ecs)
                stop_ecs_service
                ;;
            start-grafana)
                start_grafana_service
                ;;
            stop-grafana)
                stop_grafana_service
                ;;
            start-rds)
                start_rds_database
                ;;
            stop-rds)
                stop_rds_database
                ;;
            delete-nat)
                delete_nat_gateway
                ;;
            recreate-nat)
                recreate_nat_gateway
                ;;
            delete-alb)
                delete_alb
                ;;
            recreate-alb)
                recreate_alb
                ;;
            status|stat)
                check_all_resources_status
                ;;
            cost)
                estimate_cost_savings
                ;;
            cost-details)
                show_cost_details
                ;;
            menu)
                interactive_menu
                ;;
            help|--help|-h)
                print_header "USAGE"
                echo "Usage: $0 [COMMAND]"
                echo ""
                echo "Basic Commands:"
                echo "  start, start-all      Start all resources (ECS + RDS)"
                echo "  stop, stop-all        Stop all resources (ECS + RDS)"
                echo "  start-ecs             Start ECS service only"
                echo "  stop-ecs              Stop ECS service only"
                echo "  start-rds             Start RDS database only"
                echo "  stop-rds              Stop RDS database only"
                echo ""
                echo "Advanced Commands (Infrastructure):"
                echo "  delete-nat            Delete NAT Gateway (saves ~\$0.045/hour)"
                echo "  recreate-nat          Recreate NAT Gateway via Terraform"
                echo "  delete-alb            Delete Load Balancer (saves ~\$0.016/hour)"
                echo "  recreate-alb          Recreate Load Balancer via Terraform"
                echo ""
                echo "Status & Information:"
                echo "  status, stat          Check all resources status"
                echo "  cost                  View cost savings breakdown"
                echo "  cost-details          View detailed cost analysis"
                echo ""
                echo "Other:"
                echo "  menu                  Open interactive menu"
                echo "  help                  Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 start              # Start all resources"
                echo "  $0 stop               # Stop all resources"
                echo "  $0 status             # Check resource status"
                echo "  $0 delete-nat         # Delete NAT Gateway"
                echo "  $0 cost               # View cost breakdown"
                echo "  $0                    # Open interactive menu (default)"
                ;;
            *)
                print_error "Unknown command: $1"
                echo "Run '$0 help' for usage information"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
