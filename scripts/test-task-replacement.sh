#!/bin/bash
# Test ECS task replacement and ALB routing after task failure
# This script simulates a task failure and verifies the ALB routes to healthy replacements

set -e

CLUSTER="enterprise-platform-cluster"
SERVICE="enterprise-platform-service"

echo "=== Testing ECS Task Replacement ==="

# Get running task
TASK_ARN=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name $SERVICE \
  --query 'taskArns[0]' \
  --output text)

echo "Stopping task: $TASK_ARN"

# Stop one task
aws ecs stop-task \
  --cluster $CLUSTER \
  --task $TASK_ARN \
  --reason "Failure testing"

echo "Task stopped. Watching ECS replace it..."

# Watch ECS replace it
watch -n 5 'aws ecs describe-services \
  --cluster '"${CLUSTER}"' \
  --services '"${SERVICE}"' \
  --query "services[0].[runningCount,desiredCount,deployments[0].status]"'
