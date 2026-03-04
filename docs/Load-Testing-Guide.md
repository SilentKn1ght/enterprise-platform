# Load Testing & ECS Scaling Monitoring Guide

## Overview

This guide walks you through performing load testing on your enterprise application and monitoring ECS auto-scaling behavior.

## Architecture

- **Load Generator**: k6 (performance testing tool)
- **Target**: Application Load Balancer (ALB) → ECS Service
- **Monitoring**: CloudWatch metrics + ECS monitoring
- **Scaling**: Auto Scaling Group for EC2 instances

## Prerequisites

1. **AWS Access**: Credentials configured with access to:
   - ECS cluster: `enterprise-platform-dev-cluster`
   - ECS service: `enterprise-platform-dev-service`
   - CloudWatch for metrics
   - Auto Scaling Groups

2. **Tools Installed**:
   - `k6` - Load testing tool (already installed)
   - `aws-cli` - For AWS interactions
   - Bash shell

3. **Network Access**:
   - Access to your ALB DNS endpoint
   - AWS API access

## ALB Endpoint

```
http://enterprise-platform-alb-1240013568.eu-north-1.elb.amazonaws.com
```

## Load Testing Profiles

The setup includes three test profiles:

### Profile 1: Baseline Load
- **Duration**: 1 minute
- **Users**: 10 concurrent
- **Target**: 10 req/s
- **Purpose**: Establish baseline performance

### Profile 2: Medium Load  
- **Duration**: 2 minutes
- **Users**: 50 concurrent
- **Target**: 50 req/s
- **Purpose**: Monitor scaling trigger

### Profile 3: High Load (Full Spike)
- **Duration**: 5 minutes
- **Users**: 100 concurrent
- **Target**: 1,000 req/s
- **Purpose**: Test auto-scaling under stress

## Running the Load Test

### Option 1: Full Test with Monitoring (Recommended)

```bash
cd /home/silentkn1ght/projects/enterprise-platform
bash scripts/load-test-with-monitoring.sh
```

This runs:
- k6 load test (17 minutes total)
- Real-time ECS monitoring alongside
- Captures task counts, CPU, memory
- Logs scaling events
- Saves results to `load-test-results.log`

**Expected behavior:**
1. First 2 minutes: Ramp to 10 VUs (minimal scaling)
2. Minutes 2-5: Scale to 50 VUs (may trigger scale-out)
3. Minutes 5-10: Spike to 100 VUs (definite scale-out)
4. Minutes 10-17: Ramp down and cleanup

### Option 2: Live Monitoring (Separate Terminal)

While the load test runs, monitor ECS activity in real-time:

```bash
bash scripts/monitor-ecs-live.sh
```

This provides:
- Real-time task counts (Desired, Running, Pending)
- Auto Scaling Group instance counts
- CPU and Memory utilization
- Recent scaling activities
- Service status

**Refresh interval**: 5 seconds

### Option 3: K6 Direct Test

Run k6 directly with custom parameters:

```bash
export ALB_DNS="enterprise-platform-alb-1240013568.eu-north-1.elb.amazonaws.com"
k6 run scripts/load-test-k6.js
```

## Interpreting Results

### ECS Task Scaling

Watch for these patterns:

| Metric | Meaning |
|--------|---------|
| **Running** count increases | Tasks being started (scale-out in progress) |
| **Pending** count > 0 | Tasks waiting for resources (EC2 instance scaling) |
| **Desired** increases | Auto-scaler fired and requested more tasks |

### CloudWatch Metrics

**Type 1: Container Metrics**
- `CPUUtilization`: % CPU per task
- `MemoryUtilization`: % RAM per task
- `TaskCount`: Number of running tasks

**Type 2: Service Metrics**
- Request count
- Request latency (p50, p95, p99)
- Error rates

**Type 3: EC2 Metrics** (via Auto Scaling Group)
- GroupInServiceInstances
- GroupTerminatingInstances
- GroupDesiredCapacity

### Scaling Triggers

Default thresholds (see Terraform config):

```
CPU >= 70%  → Scale out (+1 task)
Memory >= 80% → Scale out (+1 task)
CPU < 30% (5 min) → Scale in (-1 task)
```

### Performance Thresholds

The test validates:
- 95th percentile latency < 1000ms
- 99th percentile latency < 2000ms
- Error rate < 5%

## Monitoring During Test

### Key Metrics to Track

1. **Response times**
   - Baseline (0-2 min): Should be <100ms
   - Medium load (2-5 min): Should be <300ms
   - High load (5-10 min): Should be <500-1000ms

2. **Error rates**
   - Should remain < 1% throughout
   - Spike indicates overload or scaling failure

3. **Task scaling**
   - 0-2 min: 2-3 tasks running
   - 2-5 min: 5-8 tasks running
   - 5-10 min: 10-20 tasks running

4. **Instance scaling**
   - Watch EC2 instances scale from 1 to 2-3 nodes
   - Should happen within 1-2 minutes of CPU spike

## Output Logs

### Load Test Results

File: `load-test-results.log`

Contains:
- All k6 output including summary statistics
- ECS monitoring data (sampled every 5 seconds)
- Scaling events captured during test
- Final state comparison

### ECS Scaling Events Log

File: `ecs-scaling-events.log` (auto-generated)

Example event:
```
Task started by elastic load balancer
ECS task started by autoscaler
Container started
```

## Troubleshooting

### Issue: "no such host" DNS errors

**Cause**: Network connectivity issues
**Solution**: 
- Run from an EC2 instance in the same VPC
- Or ensure ALB is publicly accessible
- Test: `curl http://enterprise-platform-alb-1240013568.eu-north-1.elb.amazonaws.com/health`

### Issue: Tasks not scaling (Pending remains 0)

**Possible causes**:
1. ASG at max capacity - check in AWS Console
2. Scaling policy not attached - verify in ASG config
3. Insufficient resources - check available CPU/memory
4. IAM permissions - verify role has scaling permissions

**Solution**: 
```bash
# Check ASG configuration
aws autoscaling describe-auto-scaling-groups \
  --region eu-north-1 \
  --query 'AutoScalingGroups[?Tags[?Value==`enterprise-platform-dev-cluster`]]'
```

### Issue: High error rates during spike

**Normal behavior**: Some errors (< 5%) expected under extreme load
**Concerning**: If > 10% or 5xx errors spike

**Solution**:
- Reduce load (edit k6 stages in load-test-k6.js)
- Check application logs: `aws logs tail /ecs/enterprise-platform-dev`
- Verify RDS connection limits
- Check ALB target health

### Issue: Metrics show "N/A"

**Cause**: CloudWatch data not yet available (initial warmup period)
**Solution**: Wait 5-10 minutes for metrics to populate

## Advanced: Custom Load Test Profile

Edit [load-test-k6.js](load-test-k6.js) to customize:

```javascript
export let options = {
  stages: [
    { duration: '3m', target: 20 },  // Custom ramp-up
    { duration: '5m', target: 20 },  // Sustain longer
    { duration: '2m', target: 100 }, // Aggressive spike
    { duration: '3m', target: 0 },   // Gradual cooldown
  ],
  // Add custom thresholds
  thresholds: {
    http_req_duration: ['p(99)<2000'],
    http_req_failed: ['rate<0.02'],
  },
};
```

## CloudWatch Dashboard

Access through AWS Console:

1. Go to CloudWatch → Dashboards
2. Look for pre-configured dashboards:
   - `application-overview` - Overall performance
   - `system-metrics` - Infrastructure metrics
   - `Alerts-Overview` - Alert status
3. Select time range matching test duration

## Post-Test Analysis

1. **Export metrics to CSV**
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/ECS \
     --metric-name CPUUtilization \
     --dimensions Name=ClusterName,Value=enterprise-platform-dev-cluster \
     --start-time 2026-03-03T21:00:00Z \
     --end-time 2026-03-03T21:30:00Z \
     --period 60 \
     --statistics Average
   ```

2. **Analyze logs**
   ```bash
   # Get full test results
   tail -100 load-test-results.log
   
   # Extract performance summary
   grep "Summary" load-test-results.log
   ```

3. **Generate report**
   - Compare baseline vs. peak performance
   - Document scaling latency
   - Identify bottlenecks
   - Recommend capacity adjustments

## Next Steps

1. **Initial Run**: Execute `load-test-with-monitoring.sh` to establish baseline
2. **Monitor**: Use `monitor-ecs-live.sh` in parallel terminal
3. **Analyze**: Review CloudWatch dashboards during test
4. **Iterate**: Adjust load profiles and re-test
5. **Document**: Save results for comparison

## Performance Targets

- **P50 latency**: < 100ms
- **P95 latency**: < 500ms
- **P99 latency**: < 1000ms
- **Error rate**: < 1%
- **Scale-out time**: < 3 minutes from spike detection
- **Scale-in time**: < 10 minutes after load reduction

## Support & Debugging

For detailed metrics:
```bash
# Get service metrics
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1

# Get Auto Scaling Group activity
aws autoscaling describe-scaling-activities \
  --region eu-north-1 \
  --max-records 10

# Check application logs
aws logs tail /ecs/enterprise-platform-dev --follow
```
