#!/bin/bash
# Test health check failure and ALB target replacement
# This script scales services to 0 to simulate unhealthy targets and verifies ALB behavior

set -e

CLUSTER="enterprise-platform-cluster"
SERVICE="enterprise-platform-service"

echo "=== Testing Health Check Failure and ALB Recovery ==="

# Get ALB DNS
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)
TARGET_GROUP_ARN=$(terraform -chdir=terraform output -raw target_group_arn)

echo "ALB DNS: $ALB_DNS"
echo "Target Group ARN: $TARGET_GROUP_ARN"

# Trigger unhealthy state by scaling to 0
echo "Scaling service to 0 to trigger unhealthy state..."
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --desired-count 0

echo "Waiting for targets to become unhealthy..."
sleep 30

# Watch ALB target health
echo "Target health status:"
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]" \
  --output table

# Check CloudWatch alarm
echo "CloudWatch alarm status:"
aws cloudwatch describe-alarms \
  --alarm-names enterprise-platform-alb-unhealthy-hosts \
  --query 'MetricAlarms[0].[StateValue,StateReason]' \
  --output text

# Verify ALB returns errors
echo "Testing API (should fail with unavailable targets):"
curl -s http://$ALB_DNS/health || echo "API unavailable (expected)"

# Restore service
echo "Restoring service to desired count of 2..."
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --desired-count 2

# Wait for recovery
echo "Waiting for tasks to start and become healthy..."
sleep 120

# Check target health again
echo "Target health after recovery:"
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" \
  --output table

# Verify ALB responds
echo "Testing API recovery:"
curl -s http://$ALB_DNS/health | jq .

echo "✓ Health check failure test completed"
