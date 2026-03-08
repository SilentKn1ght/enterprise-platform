# Troubleshooting Guide

**Last Updated:** March 8, 2026  
**Quick Links:** [Deployment Issues](#deployment-issues) | [Runtime Issues](#runtime-issues) | [Database Issues](#database-issues) | [Networking Issues](#networking-issues)

---

## Quick Diagnosis

Not sure what's wrong? Start here:

```
Is the application running?
  → YES: Check application logs (below)
  → NO: Go to "Application Won't Start"

Are you getting errors?
  → Connection errors: Go to "Database Issues"
  → Timeout errors: Go to "Performance Issues"
  → Request errors: Check application logs

Is it slow?
  → Yes: Go to "Performance Issues"
  
Is nobody seeing your application?
  → Can't access ALB: Go to "Network Issues"
  → 503/unhealthy: Go to "Application Won't Start"
```

---

## Deployment Issues

### Docker Image Won't Build

**Error:** `docker build` fails with compilation errors

**Solution:**
```bash
# 1. Check Node.js version matches package.json
docker run --rm node:18-alpine --version

# 2. Clear Docker cache and rebuild
docker system prune -a
docker build --no-cache -t enterprise-platform:latest .

# 3. Check for syntax errors
cd services/api
npm run lint

# 4. Check dependencies
npm install
npm list

# Then retry build
docker build -t enterprise-platform:latest .
```

### ECR Push Fails

**Error:** `denied: User is not authorized to perform...`

**Solution:**
```bash
# 1. Verify AWS credentials
aws sts get-caller-identity

# 2. Check IAM permissions for ECR
aws iam get-user-policy --user-name [YOUR_USER] --policy-name [POLICY_NAME]

# 3. Re-authenticate with ECR
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin [ACCOUNT].dkr.ecr.eu-north-1.amazonaws.com

# 4. Verify repository exists
aws ecr describe-repositories --region eu-north-1

# 5. Retry push
docker push [ACCOUNT].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:latest
```

### Terraform Apply Fails

**Error:** `Error: Error creating ECS Service...`

**Solution:**
```bash
# 1. Validate Terraform syntax
terraform validate

# 2. Check variable file for errors
terraform fmt terraform.tfvars

# 3. Check AWS account limits
aws service-quotas list-service-quotas --service-code ecs

# 4. Check if resources already exist
aws ecs list-clusters --region eu-north-1
aws rds describe-db-instances --region eu-north-1

# 5. Try again with more detail
terraform apply -lock=false  # Remove lock if stuck
```

**Common cause:** RDS free-tier limitation on backup retention

**Solution:**
```bash
# Edit RDS configuration for free tier compatibility
nano terraform/modules/rds/main.tf

# Change these lines:
backup_retention_period = 1  # was 7 (free tier max)
performance_insights_enabled = false  # was true
performance_insights_retention_period = 7  # comment out

# Then retry
terraform apply
```

### Terraform State Corrupted

**Error:** `Error acquiring lock...` or state mismatch

**Solution:**
```bash
# 1. Check state file integrity
terraform state list

# 2. Backup current state
cp terraform/terraform.tfstate terraform/terraform.tfstate.backup

# 3. Refresh state (match actual AWS resources)
terraform refresh

# 4. If still broken, force unlock
terraform force-unlock [LOCK_ID]

# 5. Reapply
terraform apply
```

---

## Runtime Issues

### Application Won't Start

**Symptom:** Tasks constantly restarting, ALB shows "unhealthy"

**Investigation:**
```bash
# 1. Check task logs for startup errors
aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1

# Look for errors like:
# - "Cannot find module..."
# - "ENOENT: no such file..."
# - "listen EADDRINUSE: address already in use..."

# 2. Check task definition version
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1 \
  --query 'services[0].taskDefinition'

# 3. View the actual task definition
aws ecs describe-task-definition \
  --task-definition [FROM_ABOVE] \
  --region eu-north-1 | jq '.taskDefinition.containerDefinitions'
```

**Common causes & fixes:**

**Cause:** Missing environment variable
```bash
# Check what's defined
aws ecs describe-task-definition \
  --task-definition enterprise-platform-dev \
  --region eu-north-1 | grep -i "environment"

# Add missing variable in terraform/modules/ecs/main.tf
environment = [
  {
    name  = "DATABASE_URL"
    value = "postgresql://user:pass@host:5432/db"
  }
]

terraform apply
```

**Cause:** Invalid Docker image reference
```bash
# Verify image exists and is accessible
aws ecr describe-images \
  --repository-name enterprise-platform \
  --region eu-north-1

# Update ECR image URI if wrong
terraform.tfvars
# ecr_image_uri = "[ACCOUNT].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:latest"

terraform apply
```

**Cause:** Out of memory (OOM)
```bash
# Check memory usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=enterprise-platform-dev-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average

# Increase memory
terraform.tfvars
# ecs_task_memory = 1024  (was 512)

terraform apply
```

### Application Returns 502/503 Errors

**Cause:** Backend (ECS tasks) are unhealthy or unavailable

**Solution:**
```bash
# 1. Check task health
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1 \
  --query 'services[0].events'

# 2. Check target group health
aws elbv2 describe-target-health \
  --target-group-arn [ARN] \
  --region eu-north-1

# 3. Check application logs
aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1

# 4. Restart tasks
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1

# 5. Verify health endpoint
curl -v http://[ALB_DNS]/health
```

### Application Returns 500 Errors

**Cause:** Application code is throwing unhandled exceptions

**Solution:**
```bash
# 1. Find the error in logs
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "ERROR" \
  --region eu-north-1

# 2. Identify which endpoint is failing
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "[time, request_id, method, path, status >= 500]" \
  --region eu-north-1

# 3. Check application logs locally
cd services/api
npm test  # Run tests to find issue

# 4. Fix the bug
# Edit app.js or relevant file
# Test locally: npm start

# 5. Deploy fix
git add -A
git commit -m "Fix endpoint error"
git push origin main

# GitHub Actions auto-deploys (3-5 minutes)
```

### High Response Times (Slow API)

**Symptom:** Requests taking > 1 second

**Investigation:**
```bash
# 1. Check slowest endpoints
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "[time, request_id, method, path, duration] duration > 1000" \
  --region eu-north-1

# 2. Check database query times
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# 3. Check CPU/Memory usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=enterprise-platform-dev-service \
  --statistics Average \
  --period 60 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

**Solutions:**

**Add caching:**
```bash
# Cache expensive queries
# Edit services/api/app.js
app.get('/api/expensive', cache('1 minute'), expensiveHandler);

# Test locally: npm test
# Deploy: git push origin main
```

**Optimize queries:**
```bash
# Add database index
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "CREATE INDEX idx_users_email ON users(email);"

# Test query performance
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
```

**Scale up:**
```bash
# Increase task count or size
terraform.tfvars
# max_capacity = 10  (was 6)
# ecs_task_cpu = 512  (was 256)

terraform apply
```

---

## Database Issues

### Can't Connect to Database

**Error:** `ECONNREFUSED` or `ETIMEDOUT` when connecting to RDS

**Investigation:**
```bash
# 1. Check RDS is running
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].DBInstanceStatus'

# 2. Check security group allows connections
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=enterprise-platform*rds*" \
  --region eu-north-1 | jq '.SecurityGroups[].IpPermissions'

# Should show:
# - IpProtocol: "tcp"
# - FromPort: 5432
# - ToPort: 5432
# - SourceSecurityGroupId: [ECS_SG_ID]

# 3. Test connectivity from ECS task
aws ssm start-session --target [TASK_ID] --region eu-north-1
# Then inside container:
telnet [RDS_ENDPOINT] 5432

# 4. Check RDS endpoint is correct
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].Endpoint'
```

**Solutions:**

**RDS stopped:**
```bash
aws rds start-db-instance \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# Wait 2 minutes for startup
sleep 120

# Restart ECS service
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1
```

**Security group wrong:**
```bash
# Fix via Terraform
terraform.tfvars
# Or edit in AWS Console: EC2 → Security Groups

# Find RDS security group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=enterprise-platform*rds*" \
  --region eu-north-1

# Add ECS security group as inbound rule
aws ec2 authorize-security-group-ingress \
  --group-id [RDS_SG_ID] \
  --protocol tcp \
  --port 5432 \
  --source-group [ECS_SG_ID] \
  --region eu-north-1
```

**Endpoint wrong in application:**
```bash
# Check current endpoint
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].Endpoint.Address'

# Update Terraform if needed
terraform.tfvars
# db_host = "new-endpoint.xxx.rds.amazonaws.com"

terraform apply
```

### Database Disk Full

**Symptom:** Queries failing, can't insert data

**Solution:**
```bash
# 1. Check storage
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].[AllocatedStorage, FreeStorageSpace]'

# 2. Check what's taking space
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "
  SELECT schemaname, tablename, 
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
  FROM pg_tables 
  WHERE schemaname NOT IN ('pg_catalog','information_schema')
  ORDER BY pg_total_relation_size DESC;"

# 3. Clean up old data
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "DELETE FROM logs WHERE created_at < now() - interval '90 days';"

# 4. Vacuum to reclaim space
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "VACUUM;"

# 5. If still full, increase storage
terraform.tfvars
# db_allocated_storage = 50  (was 20)
terraform apply

# Or enable auto-scaling (if not already)
# RDS auto-scales storage up to 40GB if configured
```

### Database Too Slow

**Symptom:** Queries taking > 5 seconds

**Solution:**
```bash
# 1. Find slow queries
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 5;"

# 2. Analyze query plan
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "EXPLAIN ANALYZE SELECT ... (your slow query);"

# 3. Add missing indexes
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "CREATE INDEX idx_name ON table(column);"

# 4. Check index usage
PGPASSWORD="[DB_PASS]" psql -h [RDS_ENDPOINT] \
  -U enterprise_admin -d enterprise_platform \
  -c "SELECT * FROM pg_stat_user_indexes ORDER BY idx_use DESC;"

# 5. If instance is undersized
terraform.tfvars
# db_instance_class = "db.t3.small"  (was db.t3.micro)
terraform apply
```

### Database Backup Failed

**Symptom:** Backup status shows "failed" in AWS Console

**Solution:**
```bash
# 1. Check backup history
aws rds describe-db-snapshots \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# 2. Check why it failed
aws rds describe-db-snapshots \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBSnapshots[-1].[Status, StatusMessage]'

# 3. Try manual backup
aws rds create-db-snapshot \
  --db-instance-identifier enterprise-platform-db \
  --db-snapshot-identifier manual-backup-$(date +%s) \
  --region eu-north-1

# 4. If manual fails, check storage
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 \
  --query 'DBInstances[0].FreeStorageSpace'

# If low: clean up data (see "Database Disk Full" above)
```

---

## Networking Issues

### Can't Access Application

**Symptom:** `curl http://[ALB_DNS]` returns timeout or connection refused

**Investigation:**
```bash
# 1. Check ALB exists and is active
aws elbv2 describe-load-balancers --region eu-north-1

# 2. Check security group allows traffic
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=enterprise-platform*alb*" \
  --region eu-north-1 | jq '.SecurityGroups[].IpPermissions'

# Should show:
# - IpProtocol: "tcp"
# - FromPort: 80
# - ToPort: 80
# - CidrIp: "0.0.0.0/0" (anywhere)

# 3. Check target health
aws elbv2 describe-target-health \
  --target-group-arn [ARN] \
  --region eu-north-1

# 4. Check ECS service has running tasks
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1 \
  --query 'services[0].[runningCount, desiredCount]'
```

**Solutions:**

**ALB security group wrong:**
```bash
# Fix inbound rule
aws ec2 authorize-security-group-ingress \
  --group-id [ALB_SG_ID] \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region eu-north-1

# For HTTPS (if configured)
aws ec2 authorize-security-group-ingress \
  --group-id [ALB_SG_ID] \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region eu-north-1
```

**No running ECS tasks:**
```bash
# Restart service
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --desired-count 2 \
  --force-new-deployment \
  --region eu-north-1

# Wait 1 minute for tasks to start
# Verify: curl http://[ALB_DNS]/health
```

**ALB not in public subnet:**
```bash
# Check ALB subnets
aws elbv2 describe-load-balancers \
  --region eu-north-1 \
  --query 'LoadBalancers[0].Subnets'

# These should be public subnet IDs (with IGW route)
# If wrong, delete and recreate via Terraform:
terraform destroy && terraform apply
```

### DNS Resolution Fails

**Symptom:** `nslookup [ALB_DNS]` fails (if using Route 53)

**Solution:**
```bash
# 1. Check Route 53 record exists
aws route53 list-resource-record-sets \
  --hosted-zone-id [ZONE_ID] \
  --region eu-north-1

# 2. Verify it points to ALB
aws route53 test-dns-answer \
  --hosted-zone-id [ZONE_ID] \
  --record-name enterprise-platform.example.com \
  --record-type A

# 3. Update record if wrong
aws route53 change-resource-record-sets \
  --hosted-zone-id [ZONE_ID] \
  --change-batch file://dns-update.json

# Where dns-update.json contains:
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "enterprise-platform.example.com",
      "Type": "A",
      "AliasTarget": {
        "DNSName": "[ALB_DNS]",
        "EvaluateTargetHealth": true
      }
    }
  }]
}
```

---

## Performance Issues

### Too Many Errors (High Error Rate)

**Symptom:** > 5% requests returning 5xx status

**Investigation:**
```bash
# 1. Find errors
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "500" \
  --region eu-north-1

# 2. Check which endpoint
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "[time, request_id, method, path, status >= 500]" \
  --region eu-north-1

# 3. Check application metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=app/enterprise-platform-dev-alb \
  --statistics Sum \
  --period 300 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

**Solutions:**

**Application bug:**
```bash
# Fix and redeploy
cd services/api
npm test  # Find the issue
# Edit and fix
git add -A
git commit -m "Fix error in endpoint"
git push origin main
# Wait 3-5 minutes for auto-deploy
```

**Database issue:**
```bash
# Restart database
aws rds reboot-db-instance \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# Wait 2 minutes and test
curl http://[ALB_DNS]/health
```

**Resource exhaustion:**
```bash
# Scale up
terraform.tfvars
# max_capacity = 10  (increase)
terraform apply

# Or restart tasks to clear state
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1
```

---

## Getting Help

**Still stuck?**

1. **Check logs first:**
   ```bash
   aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1
   ```

2. **Collect diagnostics:**
   ```bash
   # Run this and share output
   aws ecs describe-services \
     --cluster enterprise-platform-dev-cluster \
     --services enterprise-platform-dev-service \
     --region eu-north-1 | jq '.services[0] | {runningCount, desiredCount, status, deployments, events}'
   ```

3. **Check AWS service health:**
   - https://status.aws.amazon.com
   - Are there any service disruptions?

4. **Review related docs:**
   - [ARCHITECTURE.md](ARCHITECTURE.md) - System design
   - [OPERATIONS.md](OPERATIONS.md) - Runbooks & procedures
   - [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment steps

5. **Common AWS Console paths:**
   - ECS: https://console.aws.amazon.com/ecs
   - RDS: https://console.aws.amazon.com/rds
   - CloudWatch Logs: https://console.aws.amazon.com/logs
   - CloudWatch Metrics: https://console.aws.amazon.com/cloudwatch
