# Operations & Runbooks

**Last Updated:** March 8, 2026  
**Environment:** AWS ECS Fargate (Production-ready)

---

## Quick Start for Operations Team

If you're new here, start with:
1. **[Monitor the System](#monitoring-the-system)** - Check health every morning
2. **[Responding to Alerts](#responding-to-alerts)** - Handle incidents
3. **[Common Issues](#common-operations-issues)** - Fix problems
4. **[Logs and Debugging](#viewing-logs-and-debugging)** - Troubleshoot

---

## Monitoring the System

### Daily Health Check (5 minutes)

Start your day by verifying everything is healthy:

```bash
#!/bin/bash
# Run this every morning

# 1. Check application health
ALB=$(aws ec2 describe-load-balancers \
  --region eu-north-1 \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "Testing application..."
curl -s http://$ALB/health | jq .

# 2. Check ECS service status
echo "Checking ECS service..."
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1 \
  --query 'services[0].[runningCount,desiredCount,deployments[0].status]'

# 3. Check RDS status
echo "Checking database..."
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].[DBInstanceStatus,EngineVersion]'

# 4. Check recent errors
echo "Checking for errors..."
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --start-time $(($(date +%s) - 3600))000 \
  --filter-pattern "ERROR" \
  --region eu-north-1 | jq '.events | length'
```

**What you're looking for:**
- ✅ Health check returns 200 OK
- ✅ Running count = Desired count (all tasks healthy)
- ✅ Deployment status = "PRIMARY" (not rolling out)
- ✅ RDS status = "available"
- ✅ Error count = 0 or very low

---

## Responding to Alerts

When something breaks, use these runbooks to fix it systematically.

### Alert: Application Down

**Severity:** 🔴 CRITICAL  
**What it means:** ALB can't connect to any ECS tasks

#### Investigation (2 minutes)

```bash
# 1. Check if ECS tasks are running
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1

# Look for:
# - runningCount: Should match desiredCount
# - deployments: Should have 1 with status "PRIMARY"

# 2. If running count is 0, check what went wrong
aws ecs describe-task-definition \
  --task-definition enterprise-platform-dev:1 \
  --region eu-north-1

# 3. Check recent logs for errors
aws logs tail /ecs/enterprise-platform-dev \
  --follow \
  --region eu-north-1 \
  --max-items 50
```

#### Resolution (5 minutes)

**Option A: Quick restart**
```bash
# Force new deployment (restarts all tasks)
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1

# Wait 1-2 minutes for tasks to restart
# Verify: curl http://$ALB/health
```

**Option B: Rollback code**
If restart doesn't work, revert recent changes:
```bash
# Check recent pushes
git log --oneline -5

# Revert the problematic commit
git revert HEAD
git push origin main

# GitHub Actions automatically redeploys
# Wait 3-5 minutes
```

**Option C: Restart database**
If application won't start due to database:
```bash
# Verify RDS is running
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 | grep DBInstanceStatus

# If "stopped" or "stopping", start it:
aws rds start-db-instance \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# Wait 2 minutes for RDS to start
# Then restart ECS service (Option A)
```

#### Prevention

- Monitor application logs daily
- Set up CloudWatch alarm for task count mismatches
- Test deployments in staging first
- Keep recent deployments for quick rollback

---

### Alert: High CPU Usage (>80%)

**Severity:** 🟡 WARNING  
**What it means:** Application is consuming too much processing power

#### Investigation (2 minutes)

```bash
# 1. Check which endpoint is slow
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "[time, request_id, endpoint, status, duration] duration > 1000" \
  --region eu-north-1

# 2. Check request rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/enterprise-platform-dev-alb \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --region eu-north-1

# 3. Check memory usage (to rule out memory leak)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=enterprise-platform-dev-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --region eu-north-1
```

#### Resolution

**Option A: Scale out (add tasks)**
```bash
# Increase maximum capacity
cd terraform
nano terraform.tfvars
# Change: max_capacity = 10  (was 6)
terraform apply

# This allows auto-scaling to add more tasks
# Should happen automatically within 5 minutes
```

**Option B: Optimize code**
```bash
# Identify slow endpoint from logs
# Fix the code
# Push change (auto-deploys via CI/CD)
git add -A
git commit -m "Optimize slow endpoint"
git push origin main

# New deployment starts (3-5 minutes)
```

**Option C: Increase task size**
```bash
# For better single-task performance
cd terraform
nano terraform.tfvars
# Change: ecs_task_cpu = "512"  (was 256)
# Change: ecs_task_memory = "1024"  (was 512)
terraform apply

# Warning: Costs will roughly double
```

#### Prevention

- Load test before releasing new code
- Monitor slowest endpoints in Grafana
- Set alerts for response time (>1 second)
- Review CPU trends weekly

---

### Alert: High Memory Usage (>80%)

**Severity:** 🟡 WARNING  
**What it means:** Application is close to running out of memory

#### Investigation (2 minutes)

```bash
# 1. Check memory trend
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=enterprise-platform-dev-service \
  --start-time $(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region eu-north-1

# 2. Check if memory is growing (memory leak)
# Look for: steadily increasing values

# 3. Check application logs for memory warnings
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "heap|memory|OutOfMemory" \
  --region eu-north-1
```

#### Resolution

**Option A: Restart tasks (short-term fix)**
```bash
# Force restart of all tasks
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1

# This clears memory and gives a fresh start
# If memory grows right back: you have a memory leak
```

**Option B: Increase memory (long-term)**
```bash
# Allocate more memory per task
cd terraform
nano terraform.tfvars
# Change: ecs_task_memory = "1024"  (was 512)
terraform apply

# Tasks will restart with more memory available
```

**Option C: Fix memory leak**
```bash
# If memory steadily grows:
# 1. Check application code for leaks
# 2. Profile with Node.js debugging:
node --inspect=0.0.0.0:9229 app.js
# 3. Use Chrome DevTools to inspect heap

# After fix:
git add -A
git commit -m "Fix memory leak in cache layer"
git push origin main
```

#### Prevention

- Monitor memory trends in Grafana
- Set memory alert at 70% (warning before 80%)
- Profile application under load
- Regular restarts (auto-restart tasks weekly)

---

### Alert: High Database Connections (>100)

**Severity:** 🟡 WARNING  
**What it means:** Database connection pool may be exhausted

#### Investigation (2 minutes)

```bash
# 1. Check connection count
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].Endpoint'

# 2. Query actual connections in database
# (requires connecting to RDS)
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

# 3. Check for idle connections eating pool
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "SELECT * FROM pg_stat_activity WHERE state='idle' AND query_start < now() - interval '5 minutes';"
```

#### Resolution

**Option A: Kill idle connections**
```bash
# Dangerous - but sometimes necessary
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity 
      WHERE state='idle' AND query_start < now() - interval '10 minutes';"

# Then restart ECS service to refresh connections
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1
```

**Option B: Increase max connections**
```bash
# Edit RDS parameter group (AWS Console)
# Or via Terraform: modify max_connections parameter
# Default: 200 for db.t3.micro
# Note: Requires database reboot
```

**Option C: Reduce connection pool**
```bash
# If app is leaking connections:
# Check application connection pool configuration
# Reduce pool size
# Deploy code fix

git add -A
git commit -m "Fix database connection leak"
git push origin main
```

#### Prevention

- Monitor connection count daily
- Set alert at 80 connections (out of 200)
- Implement connection pooling properly
- Regular connection audits

---

### Alert: RDS Storage Low (<2 GB free)

**Severity:** 🟡 WARNING  
**What it means:** Database disk space filling up

#### Investigation (2 minutes)

```bash
# 1. Check storage capacity
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].[AllocatedStorage,FreeStorageSpace]'

# 2. Check what's taking space
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "
  SELECT schemaname, tablename, 
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) 
  FROM pg_tables 
  WHERE schemaname NOT IN ('pg_catalog','information_schema')
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```

#### Resolution

**Option A: Clean up old data**
```bash
# Identify and archive old logs/records
# For example, logs older than 90 days:
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "DELETE FROM logs WHERE created_at < now() - interval '90 days';"

# Vacuum to reclaim space
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "VACUUM;"
```

**Option B: Increase storage**
```bash
# Edit RDS instance (requires brief downtime)
# Via Terraform:
cd terraform
nano terraform.tfvars
# Change: db_allocated_storage = "50"  (was 20)
terraform apply

# RDS will auto-scale storage anyway if configured
```

**Option C: Archive to S3**
```bash
# For long-term storage:
# Export old records to CSV
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "
  \COPY (SELECT * FROM logs WHERE created_at < now() - interval '90 days') 
  TO 'logs-archive-2026-03.csv' WITH CSV HEADER;"

# Upload to S3
aws s3 cp logs-archive-2026-03.csv \
  s3://enterprise-platform-backups/

# Delete from database
PGPASSWORD="$DB_PASSWORD" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform \
  -c "DELETE FROM logs WHERE created_at < now() - interval '90 days';"
```

#### Prevention

- Monitor storage daily
- Set alert at 3 GB free (out of 20 GB)
- Archive logs regularly
- Clean up old test data

---

## Common Operations Issues

### Issue: Deployment stuck in "rolling out"

**Cause:** New task definition not passing health checks

**Solution:**
```bash
# 1. Check task definition validation
aws ecs describe-task-definition \
  --task-definition enterprise-platform-dev:LATEST \
  --region eu-north-1 | jq '.taskDefinition | keys'

# 2. Check task logs for startup errors
aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1

# 3. Rollback to previous version
git revert HEAD
git push origin main

# Or manually:
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --task-definition enterprise-platform-dev:[PREVIOUS_REVISION] \
  --region eu-north-1
```

### Issue: Database in "backing-up" state for hours

**Cause:** Old backup still running (rare)

**Solution:**
```bash
# 1. Check backup status
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 | grep PendingModifiedValues

# 2. Check backup progress
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 | grep -i backup

# 3. If stuck, reboot database
aws rds reboot-db-instance \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# Wait 2-3 minutes for reboot
```

### Issue: ALB shows unhealthy targets

**Cause:** ECS tasks failing health checks

**Solution:**
```bash
# 1. View detailed target health
aws elbv2 describe-target-health \
  --target-group-arn [TARGET_GROUP_ARN] \
  --region eu-north-1

# 2. Check application logs
aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1

# 3. Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*enterprise-platform*ecs*" \
  --region eu-north-1

# 4. Verify health endpoint works
ALB=$(aws ec2 describe-load-balancers \
  --region eu-north-1 \
  --query 'LoadBalancers[0].DNSName' --output text)
curl -v http://$ALB/health

# 5. Restart ECS tasks
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1
```

---

## Viewing Logs and Debugging

### Real-time Logs

```bash
# Follow application logs as they occur
aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1

# Last 100 lines
aws logs tail /ecs/enterprise-platform-dev --max-items 100 --region eu-north-1

# Last 1 hour
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --start-time $(($(date +%s) - 3600))000 \
  --region eu-north-1
```

### Search Logs

```bash
# Find all errors
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "ERROR" \
  --region eu-north-1

# Find specific endpoint calls
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "GET /api/users" \
  --region eu-north-1

# Find slow requests (>1 second)
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "[time, request_id, method, path, status, duration] duration > 1000" \
  --region eu-east-1
```

### Database Logs

```bash
# View most recent RDS logs
aws rds describe-db-log-files \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# Download specific log
aws rds download-db-log-file-portion \
  --db-instance-identifier enterprise-platform-db \
  --log-file-name [LOG_FILE_NAME] \
  --initial-skip 0 \
  --number-of-lines 100 \
  --region eu-north-1

# Query for slow queries
aws rds describe-db-log-files \
  --db-instance-identifier enterprise-platform-db \
  --filters Name=filename,Values=postgresql.log \
  --region eu-north-1
```

### Direct Database Access

```bash
# Connect to database directly
export PGPASSWORD="[DB_PASSWORD]"
psql -h [RDS_ENDPOINT] \
  -U enterprise_admin \
  -d enterprise_platform

# Common diagnostic queries:
SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;  -- Connections
SELECT * FROM pg_stat_statements ORDER BY mean_time DESC;  -- Slow queries
SELECT schemaname, tablename, seq_scan FROM pg_stat_user_tables;  -- Table info
```

---

## Scheduled Maintenance

### Weekly Tasks

```bash
# Monday: Review logs and metrics from weekend
aws logs tail /ecs/enterprise-platform-dev --start-time "1 week ago" --region eu-north-1

# Wednesday: Check database size and clean old data
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 --query 'DBInstances[0].AllocatedStorage'

# Friday: Verify backups completed
aws rds describe-db-snapshots \
  --db-instance-identifier enterprise-platform-db  \
  --region eu-north-1 --query 'DBSnapshots[-1].[SnapshotCreateTime, Status]'
```

### Monthly Tasks

```bash
# Review cost trends
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '1 month ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=SERVICE

# Check for unused resources (old AMIs, EBS volumes, IPs)
aws ec2 describe-volumes --filters Name=status,Values=available --region eu-north-1

# Review security group changes
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*enterprise-platform*" \
  --region eu-north-1
```

---

## Cost Control Operations

### Monitor Spending

```bash
# Daily: Check if on track
aws ce get-cost-forecast \
  --time-period Start=$(date -u +%Y-%m-%d),End=$(date -u -d '30 days' +%Y-%m-%d) \
  --metric UNBLENDED_COST \
  --granularity MONTHLY \
  --region eu-north-1

# Weekly: Review service breakdown
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '7 days ago' + %Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --metrics UnblendedCost \
  --group-by Type=SERVICE
```

### Save Money (without compromising performance)

```bash
# 1. Schedule dev environment off-hours
# Stop at 6pm, start at 9am (saves €10-15/month)

# 2. Right-size instances based on metrics
# Compare CPU/Memory usage vs. allocated

# 3. Delete unused resources
# Old images in ECR, unused volumes, etc.

# 4. Buy reserved instances
# 1-year commitment saves ~35% on RDS
```

---

## Disaster Recovery Procedures

### Database Restore

```bash
# 1. List available backups
aws rds describe-db-snapshots \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# 2. Restore to new instance
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier enterprise-platform-db-restored \
  --db-snapshot-identifier [SNAPSHOT_ID] \
  --region eu-north-1

# 3. Note new endpoint
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db-restored \
  --region eu-north-1 --query 'DBInstances[0].Endpoint'

# 4. Update application to use new endpoint
# Requires code change and redeployment
```

### Full System Recovery

```bash
# If everything is broken:

# 1. Recreate infrastructure from code
cd terraform
terraform destroy  # Remove everything
terraform apply    # Recreate from scratch

# 2. Restore database from snapshot
# (see Database Restore above)

# 3. Redeploy application
git push origin main
# GitHub Actions automatically rebuilds and deploys

# Estimated time: 30-45 minutes
```

---

## Escalation Path

**When to escalate:**
1. **Can't fix within 30 minutes:** Involve senior engineer
2. **Need database expert:** Contact DBA
3. **Infrastructure failure:** Contact Cloud team
4. **Security incident:** Contact security team immediately

**Escalation contacts (update these):**
- On-call engineer: [phone/Slack]
- Cloud platform team: [contact info]
- Database expert: [contact info]
- Security: [contact info]

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [DEPLOYMENT.md](DEPLOYMENT.md) - How to deploy
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Problem solving
- [Load-Testing-Guide.md](Load-Testing-Guide.md) - Performance testing
