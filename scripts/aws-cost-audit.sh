#!/bin/bash

echo "==============================="
echo " AWS COST AUDIT REPORT"
echo "==============================="

echo ""
echo "🔎 Checking NAT Gateways..."
aws ec2 describe-nat-gateways \
  --query "NatGateways[*].[NatGatewayId,State]" \
  --output table

echo ""
echo "🔎 Checking Load Balancers..."
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[*].[LoadBalancerName,State.Code]" \
  --output table

echo ""
echo "🔎 Checking ECS Services..."
aws ecs list-clusters --query "clusterArns[]" --output text | while read cluster; do
  echo "Cluster: $cluster"
  aws ecs list-services --cluster $cluster --query "serviceArns[]" --output text | while read service; do
    aws ecs describe-services \
      --cluster $cluster \
      --services $service \
      --query "services[*].[serviceName,desiredCount,runningCount]" \
      --output table
  done
done

echo ""
echo "🔎 Checking RDS Instances..."
aws rds describe-db-instances \
  --query "DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass]" \
  --output table

echo ""
echo "🔎 Checking Fargate Tasks..."
aws ecs list-clusters --query "clusterArns[]" --output text | while read cluster; do
  aws ecs list-tasks --cluster $cluster --query "taskArns[]" --output text
done

echo ""
echo "==============================="
echo " Audit Complete"
echo "==============================="