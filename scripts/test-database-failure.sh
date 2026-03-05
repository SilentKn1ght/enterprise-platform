#!/bin/bash
# Test database connection failure scenarios
# This script temporarily breaks database connectivity to test application error handling

set -e

CLUSTER="enterprise-platform-cluster"
SERVICE="enterprise-platform-service"
DB_INSTANCE="enterprise-platform-db"

echo "=== Testing Database Connection Failure ==="

# Get RDS security group
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

echo "RDS Security Group: $RDS_SG"

# Backup current rules
echo "Backing up security group rules..."
aws ec2 describe-security-groups \
  --group-ids $RDS_SG > rds-sg-backup.json

# Get ECS security group
ECS_SG=$(terraform -chdir=terraform output -raw ecs_security_group_id)
echo "ECS Security Group: $ECS_SG"

# Get ALB DNS
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)
echo "ALB DNS: $ALB_DNS"

# Remove ingress rule (blocks database access)
echo "Blocking database access by revoking security group rule..."
aws ec2 revoke-security-group-ingress \
  --group-id $RDS_SG \
  --source-group $ECS_SG \
  --protocol tcp \
  --port 5432

echo "Waiting for application to detect database connection error..."
sleep 10

# Check application behavior
echo "Testing application API:"
curl -s http://$ALB_DNS/api/status | jq . || echo "API error (expected)"

# Check logs for database errors
echo "Checking logs for database errors:"
aws logs tail /ecs/enterprise-platform --since 5m | grep -i "database\|connection\|error" || echo "No errors logged yet"

# Restore security group rule
echo "Restoring database access..."
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --source-group $ECS_SG \
  --protocol tcp \
  --port 5432

# Verify recovery
echo "Waiting for application recovery..."
sleep 30

echo "Testing API recovery:"
curl -s http://$ALB_DNS/api/status | jq .

echo "✓ Database failure test completed"
