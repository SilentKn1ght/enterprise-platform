#!/bin/bash

# Load testing script using hey
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)
ENDPOINT="http://$ALB_DNS/health"

echo "=== Load Testing Configuration ==="
echo "Target: $ENDPOINT"
echo "Tool: hey"
echo ""

# Test 1: Baseline (low load)
echo "Test 1: Baseline - 10 req/s for 1 minute"
hey -z 60s -q 10 -c 2 $ENDPOINT

sleep 30

# Test 2: Medium load
echo ""
echo "Test 2: Medium Load - 50 req/s for 2 minutes"
hey -z 120s -q 50 -c 10 $ENDPOINT

sleep 30

# Test 3: High load (trigger auto-scaling)
echo ""
echo "Test 3: High Load - 200 req/s for 5 minutes"
hey -z 300s -q 1000 -c 50 $ENDPOINT

echo ""
echo "=== Load Test Complete ==="
echo "Check CloudWatch for auto-scaling events"
