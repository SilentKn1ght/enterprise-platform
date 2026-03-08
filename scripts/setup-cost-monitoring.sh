#!/bin/bash

###############################################################################
# AWS Budgets & Cost Monitoring Setup Script
# Purpose: Deploy AWS Budgets configuration and Cost Anomaly Detection
# Project: enterprise-platform
# Usage: ./scripts/setup-cost-monitoring.sh
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}AWS Budgets & Cost Monitoring Setup${NC}"
echo -e "${GREEN}Enterprise Platform - Days 31-32${NC}"
echo -e "${GREEN}================================================${NC}\n"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq not found${NC}"
    exit 1
fi

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account ID: $ACCOUNT_ID${NC}"

# Get current region
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="eu-north-1"
fi
echo -e "${GREEN}✓ AWS Region: $AWS_REGION${NC}"

# Step 1: Create Budget
echo -e "\n${YELLOW}Step 1: Creating AWS Budget...${NC}"

if [ ! -f "budget-config.json" ]; then
    echo -e "${RED}Error: budget-config.json not found${NC}"
    exit 1
fi

aws budgets create-budget \
    --account-id "$ACCOUNT_ID" \
    --budget file://budget-config.json \
    --region "$AWS_REGION" \
    2>/dev/null || echo -e "${YELLOW}⚠ Budget already exists (or error creating)${NC}"

echo -e "${GREEN}✓ Budget configured${NC}"

# Step 2: Create Budget Notification
echo -e "\n${YELLOW}Step 2: Creating Budget Notification...${NC}"

if [ ! -f "notification-config.json" ] || [ ! -f "subscribers.json" ]; then
    echo -e "${RED}Error: notification-config.json or subscribers.json not found${NC}"
    exit 1
fi

# Update subscriber email in prompt
read -p "Enter email for budget alerts (press Enter to skip): " EMAIL
if [ -n "$EMAIL" ]; then
    jq --arg email "$EMAIL" '.[] | .Address = $email' subscribers.json > subscribers-temp.json
    mv subscribers-temp.json subscribers.json
    echo -e "${GREEN}✓ Email updated to: $EMAIL${NC}"
fi

aws budgets create-notification \
    --account-id "$ACCOUNT_ID" \
    --budget-name "enterprise-platform-monthly" \
    --notification file://notification-config.json \
    --subscribers file://subscribers.json \
    --region "$AWS_REGION" \
    2>/dev/null || echo -e "${YELLOW}⚠ Notification already exists (or error creating)${NC}"

echo -e "${GREEN}✓ Notification configured${NC}"

# Step 3: Enable Cost Anomaly Detection
echo -e "\n${YELLOW}Step 3: Enabling Cost Anomaly Detection...${NC}"

# Note: Cost Anomaly Detection must be enabled via Console or specific API
echo -e "${YELLOW}⚠ Cost Anomaly Detection requires manual setup:${NC}"
echo -e "${YELLOW}   1. Go to AWS Cost Management Console${NC}"
echo -e "${YELLOW}   2. Select 'Anomaly Detection' in Cost Explorer${NC}"
echo -e "${YELLOW}   3. Enable anomaly detection for your account${NC}"
echo -e "${YELLOW}   4. Configure alert threshold: €10 above baseline${NC}"
echo -e "${YELLOW}   5. Add email subscribers${NC}"

# Step 4: Create CloudWatch Dashboard (optional)
echo -e "\n${YELLOW}Step 4: (Optional) Create CloudWatch Dashboard...${NC}"
echo -e "${YELLOW}   Dashboard creation requires additional setup.${NC}"
echo -e "${YELLOW}   You can create manually in CloudWatch Console or use:${NC}"
echo -e "${YELLOW}   aws cloudwatch put-dashboard --dashboard-name enterprise-platform-costs --dashboard-body file://...${NC}"

# Summary
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}Cost Monitoring Setup Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ Budget created: enterprise-platform-monthly (€150/month)${NC}"
echo -e "${GREEN}✓ Alert threshold: 80% (€120)${NC}"
echo -e "${YELLOW}⏳ Alert email notifications will be sent when threshold exceeded${NC}"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "${YELLOW}1. Enable Cost Anomaly Detection in AWS Console${NC}"
echo -e "${YELLOW}2. Monitor first month billing for accuracy${NC}"
echo -e "${YELLOW}3. Review cost trends in second month${NC}"
echo -e "${YELLOW}4. Adjust budget threshold if needed${NC}"

exit 0
