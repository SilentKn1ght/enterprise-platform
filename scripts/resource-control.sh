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
TF_LOCK_TABLE="enterprise-platform-tfstate-lock"
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

setup_terraform_password_env() {
    # Check if database password is already set as environment variable
    if [ -n "$TF_VAR_db_password" ]; then
        print_info "Using existing TF_VAR_db_password environment variable"
        return 0
    fi
    
    print_info "Database password not set. Attempting to retrieve from AWS Secrets Manager..."
    
    # Try to get password from Secrets Manager with environment-specific name first
    local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-db-password"
    
    if local db_pass=$(aws secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null); then
        
        if [ -n "$db_pass" ] && [ "$db_pass" != "null" ]; then
            export TF_VAR_db_password="$db_pass"
            print_success "Database password loaded from Secrets Manager ($secret_name)"
            return 0
        fi
    fi
    
    print_warning "Could not retrieve password from Secrets Manager"
    echo ""
    echo -e "${YELLOW}To avoid password prompts for Terraform operations:${NC}"
    echo ""
    echo "  Option 1: Set environment variable before running this script"
    echo "    $ TF_VAR_db_password='your-password' ./scripts/resource-control.sh"
    echo ""
    echo "  Option 2: Store password in AWS Secrets Manager"
    echo "    $ aws secretsmanager create-secret \\"
    echo "        --name ${PROJECT_NAME}-${ENVIRONMENT}-db-password \\"
    echo "        --secret-string 'your-password' \\"
    echo "        --region $AWS_REGION"
    echo ""
    echo "  Option 3: Add to terraform.tfvars (NOT recommended - security risk)"
    echo "    db_password = \"your-password\""
    echo ""
    
    # For now, we'll let Terraform prompt for it, but it won't be saved
    return 1
}

#################################################################################
# Terraform State Lock Handling Functions
#################################################################################

get_tfstate_bucket() {
    if [ -n "${TF_STATE_BUCKET:-}" ]; then
        echo "$TF_STATE_BUCKET"
        return 0
    fi

    # Extract S3 bucket name from convention used by this project.
    aws s3 ls --region "$AWS_REGION" 2>/dev/null | grep -oP 'enterprise-platform-tfstate-\d+' | head -1
}

terraform_init_with_backend() {
    local bucket
    bucket=$(get_tfstate_bucket)

    if [ -z "$bucket" ]; then
        print_error "Could not determine Terraform state bucket"
        echo "Set TF_STATE_BUCKET or run ./scripts/bootstrap-tfstate.sh"
        return 1
    fi

    print_info "Initializing Terraform backend with DynamoDB locking..."
    terraform init \
        -upgrade \
        -backend-config="bucket=$bucket" \
        -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
        -backend-config="region=$AWS_REGION" \
        -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
        -input=false
}

get_terraform_lock_id() {
    local bucket="$1"
    local lock_path="$2"
    
    # Try to get the lock ID from the .terraform.lock.hcl file
    if [ -f ".terraform.lock.hcl" ]; then
        grep -oP '(?<="id" = ")[^"]*' .terraform.lock.hcl | head -1
    fi
}

handle_terraform_lock_error() {
    print_warning "Terraform state lock error detected"
    echo ""
    echo -e "${CYAN}State Lock Information:${NC}"
    echo "  Lock ID: $1"
    echo "  Path: $2"
    echo "  Who: $3"
    echo "  Created: $4"
    echo ""
    
    print_warning "Options to resolve this issue:"
    echo ""
    echo "  1. Wait for lock to expire (may take several minutes)"
    echo "  2. Force unlock (if you're sure no other process is running Terraform)"
    echo "  3. Re-run from CI workflow to avoid local lock contention"
    echo ""
}

attempt_terraform_plan_with_retry() {
    local target="$1"
    local plan_file="$2"
    local max_retries=3
    local retry_count=0
    
    # Try to setup password environment variable (won't fail if not found)
    setup_terraform_password_env || true
    
    print_info "Attempting terraform plan (with lock error handling)..."
    
    while [ $retry_count -lt $max_retries ]; do
        local output
        if output=$(terraform plan \
            -target="$target" \
            -var-file="terraform.tfvars" \
            -lock-timeout=2m \
            -out="$plan_file" \
            -input=false \
            2>&1); then
            echo "$output"
            print_success "Terraform plan succeeded"
            return 0
        else
            echo "$output"
            
            # Check if error is about state lock
            if echo "$output" | grep -q "Error acquiring the state lock"; then
                retry_count=$((retry_count + 1))
                
                if [ $retry_count -lt $max_retries ]; then
                    print_warning "State lock detected. Waiting before retry ($retry_count/$max_retries)..."
                    sleep $((15 + retry_count * 10))
                else
                    print_error "Terraform plan failed after $max_retries retries due to state lock"
                    echo ""
                    echo -e "${YELLOW}To resolve safely:${NC}"
                    echo "  1. Ensure no other Terraform run is active"
                    echo "  2. Retry this command"
                    echo "  3. Force-unlock only as a last resort"
                    echo ""
                    return 1
                fi
            else
                print_error "Terraform plan failed (non-lock error)"
                return 1
            fi
        fi
    done
    
    return 1
}

attempt_terraform_apply_with_lock_handling() {
    local plan_file="$1"
    
    print_info "Applying Terraform plan with lock error handling..."
    
    local output
    if output=$(terraform apply \
        -lock-timeout=2m \
        -input=false \
        "$plan_file" 2>&1); then
        echo "$output"
        print_success "Terraform apply succeeded"
        return 0
    else
        echo "$output"
        print_error "Terraform apply failed"
        if echo "$output" | grep -q "Error acquiring the state lock"; then
            print_warning "State lock preventing apply. Consider:"
            echo "  1. Wait a few minutes and try again"
            echo "  2. Check if another terraform process is running"
            echo "  3. Use 'terraform force-unlock <LOCK_ID>' if safe"
        fi
        return 1
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
    
    setup_terraform_password_env || true

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/../terraform"

    if ! terraform_init_with_backend; then
        print_error "Terraform init failed"
        cd - > /dev/null
        return 1
    fi

    print_info "Planning NAT Gateway destroy..."
    if ! terraform plan \
        -destroy \
        -target="module.networking.aws_nat_gateway.main" \
        -var-file="terraform.tfvars" \
        -lock-timeout=2m \
        -out="tfplan_nat_destroy" \
        -input=false; then
        print_error "Failed to create destroy plan for NAT Gateway"
        cd - > /dev/null
        return 1
    fi

    if ! confirm "Apply Terraform destroy for NAT Gateway?"; then
        print_warning "Operation cancelled"
        rm -f tfplan_nat_destroy
        cd - > /dev/null
        return
    fi

    if ! attempt_terraform_apply_with_lock_handling "tfplan_nat_destroy"; then
        print_error "Terraform destroy apply failed"
        rm -f tfplan_nat_destroy
        cd - > /dev/null
        return 1
    fi

    rm -f tfplan_nat_destroy
    cd - > /dev/null

    print_success "NAT Gateway destroy completed via Terraform"
    sleep 5
    check_nat_gateway_status
}

recreate_nat_gateway() {
    print_header "RECREATE NAT GATEWAY"
    
    print_info "This will recreate the NAT Gateway for outbound internet access"
    if ! confirm "Recreate NAT Gateway?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    # Setup password environment variable early (before changing directories)
    setup_terraform_password_env || true
    
    print_info "Running Terraform to recreate NAT Gateway..."
    
    # Save current directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/../terraform"
    
    # Initialize terraform with explicit backend locking config
    if ! terraform_init_with_backend; then
        print_error "Terraform init failed"
        cd - > /dev/null
        return 1
    fi
    
    echo ""
    print_info "Planning NAT Gateway changes..."
    
    # Attempt plan with lock error handling
    if ! attempt_terraform_plan_with_retry "module.networking.aws_route_table.private" "tfplan_nat"; then
        print_error "Failed to create Terraform plan"
        cd - > /dev/null
        return 1
    fi
    
    echo ""
    print_warning "Review the plan above. This will:"
    echo "  1. Create new Elastic IP"
    echo "  2. Create NAT Gateway"
    echo "  3. Route private traffic through NAT"
    echo ""
    
    if ! confirm "Apply Terraform changes?"; then
        print_warning "Operation cancelled. Run 'rm tfplan_nat' to clean up."
        cd - > /dev/null
        return
    fi
    
    echo ""
    print_info "Applying Terraform changes..."
    
    if ! attempt_terraform_apply_with_lock_handling "tfplan_nat"; then
        print_error "Terraform apply failed"
        cd - > /dev/null
        return 1
    fi
    
    print_success "NAT Gateway recreated!"
    
    # Cleanup plan file
    rm -f tfplan_nat
    
    cd - > /dev/null
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
    
    setup_terraform_password_env || true

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/../terraform"

    if ! terraform_init_with_backend; then
        print_error "Terraform init failed"
        cd - > /dev/null
        return 1
    fi

    print_info "Planning ALB destroy..."
    if ! terraform plan \
        -destroy \
        -target="module.alb.aws_lb.main" \
        -target="module.alb.aws_lb_target_group.app" \
        -target="module.alb.aws_lb_listener.http" \
        -target="module.alb.aws_cloudwatch_metric_alarm.alb_unhealthy_hosts" \
        -target="module.alb.aws_cloudwatch_metric_alarm.alb_target_response_time" \
        -var-file="terraform.tfvars" \
        -lock-timeout=2m \
        -out="tfplan_alb_destroy" \
        -input=false; then
        print_error "Failed to create destroy plan for ALB"
        cd - > /dev/null
        return 1
    fi

    if ! confirm "Apply Terraform destroy for ALB resources?"; then
        print_warning "Operation cancelled"
        rm -f tfplan_alb_destroy
        cd - > /dev/null
        return
    fi

    if ! attempt_terraform_apply_with_lock_handling "tfplan_alb_destroy"; then
        print_error "Terraform destroy apply failed"
        rm -f tfplan_alb_destroy
        cd - > /dev/null
        return 1
    fi

    rm -f tfplan_alb_destroy
    cd - > /dev/null

    print_success "ALB destroy completed via Terraform"
    sleep 5
    check_alb_status
}

recreate_alb() {
    print_header "RECREATE APPLICATION LOAD BALANCER"
    
    print_info "This will recreate the ALB for load balancing"
    if ! confirm "Recreate ALB?"; then
        print_warning "Operation cancelled"
        return
    fi
    
    # Setup password environment variable early (before changing directories)
    setup_terraform_password_env || true
    
    print_info "Running Terraform to recreate ALB..."
    
    # Save current directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/../terraform"
    
    # Initialize terraform with explicit backend locking config
    if ! terraform_init_with_backend; then
        print_error "Terraform init failed"
        cd - > /dev/null
        return 1
    fi
    
    echo ""
    print_info "Planning ALB changes..."
    
    # Attempt plan with lock error handling
    if ! attempt_terraform_plan_with_retry "module.alb" "tfplan_alb"; then
        print_error "Failed to create Terraform plan"
        cd - > /dev/null
        return 1
    fi
    
    echo ""
    print_warning "Review the plan above. This will create:"
    echo "  1. Application Load Balancer"
    echo "  2. Target Group for ECS tasks"
    echo "  3. HTTP Listener (port 80)"
    echo "  4. CloudWatch Alarms"
    echo ""
    
    if ! confirm "Apply Terraform changes?"; then
        print_warning "Operation cancelled. Run 'rm tfplan_alb' to clean up."
        cd - > /dev/null
        return
    fi
    
    echo ""
    print_info "Applying Terraform changes..."
    
    if ! attempt_terraform_apply_with_lock_handling "tfplan_alb"; then
        print_error "Terraform apply failed"
        cd - > /dev/null
        return 1
    fi
    
    print_success "ALB recreated!"
    
    # Cleanup plan file
    rm -f tfplan_alb
    
    cd - > /dev/null
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
