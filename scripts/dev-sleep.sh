#!/bin/bash
set -e

# -----------------------------
# CONFIGURATION
# -----------------------------
CLUSTER="enterprise-platform-dev-cluster"
SERVICE="enterprise-platform-dev-service"
DB="enterprise-platform-db"
AWS_REGION="eu-north-1"

# Change if Terraform lives elsewhere
TF_DIR="terraform"

echo "======================================="
echo "🌙 ENTERING DEV SLEEP MODE"
echo "======================================="

# -----------------------------
# 1️⃣ SCALE ECS TO ZERO (SAFE)
# -----------------------------
echo ""
echo "🔎 Checking ECS service..."

DESIRED=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE \
  --region $AWS_REGION \
  --query "services[0].desiredCount" \
  --output text)

if [ "$DESIRED" -eq 0 ]; then
  echo "ECS already scaled to 0. Skipping."
else
  echo "Scaling ECS to zero..."
  aws ecs update-service \
    --cluster $CLUSTER \
    --service $SERVICE \
    --desired-count 0 \
    --region $AWS_REGION > /dev/null
fi

echo "Waiting for ECS tasks to stop..."
while true; do
  COUNT=$(aws ecs list-tasks \
    --cluster $CLUSTER \
    --region $AWS_REGION \
    --query "length(taskArns)" \
    --output text)

  if [ "$COUNT" -eq 0 ]; then
    echo "All ECS tasks stopped."
    break
  fi

  echo "Still $COUNT task(s) running..."
  sleep 10
done

# -----------------------------
# 2️⃣ STOP RDS (SAFE)
# -----------------------------
echo ""
echo "🔎 Checking RDS status..."

STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $DB \
  --region $AWS_REGION \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text)

echo "Current RDS status: $STATUS"

if [ "$STATUS" == "stopped" ]; then
  echo "RDS already stopped. Skipping."
elif [ "$STATUS" == "stopping" ]; then
  echo "RDS already stopping. Waiting..."
  aws rds wait db-instance-stopped \
    --db-instance-identifier $DB \
    --region $AWS_REGION
  echo "RDS stopped."
elif [ "$STATUS" == "available" ]; then
  echo "Stopping RDS..."
  aws rds stop-db-instance \
    --db-instance-identifier $DB \
    --region $AWS_REGION > /dev/null

  echo "Waiting for RDS to fully stop..."
  aws rds wait db-instance-stopped \
    --db-instance-identifier $DB \
    --region $AWS_REGION

  echo "RDS stopped."
else
  echo "RDS in unexpected state ($STATUS). Skipping for safety."
fi

# -----------------------------
# 3️⃣ DESTROY NAT GATEWAY (SAFE)
# -----------------------------
echo ""
echo "🔎 Checking NAT Gateway..."

NAT_IDS=$(aws ec2 describe-nat-gateways \
  --region $AWS_REGION \
  --query "NatGateways[?State=='available'].NatGatewayId" \
  --output text)

if [ -z "$NAT_IDS" ]; then
  echo "No active NAT Gateway found. Skipping."
else
  echo "Destroying NAT Gateway via Terraform..."
  cd $TF_DIR
  terraform destroy \
    -target=module.networking.aws_nat_gateway.main \
    -auto-approve
  cd - > /dev/null
  echo "NAT Gateway destroyed."
fi

# -----------------------------
# 4️⃣ DESTROY ALB (SAFE)
# -----------------------------
echo ""
echo "🔎 Checking ALB..."

ALB_NAME="enterprise-platform-alb"

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'].LoadBalancerArn" \
  --output text)

if [ -z "$ALB_ARN" ]; then
  echo "ALB not found. Skipping."
else
  echo "Destroying ALB via Terraform..."
  cd $TF_DIR
  terraform destroy \
    -target=module.alb \
    -auto-approve
  cd - > /dev/null
  echo "ALB destroyed."
fi

echo ""
echo "======================================="
echo "✅ DEV ENVIRONMENT IS NOW SLEEPING"
echo "======================================="