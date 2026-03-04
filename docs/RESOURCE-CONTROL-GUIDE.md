# Resource Control Script - Manual Start/Stop Guide

## Overview

The `resource-control.sh` script provides a simple, manual way to start and stop your AWS resources for cost optimization. Instead of complex automation workflows, this script allows you to manually trigger resource scaling operations on demand.

## Motivation

Managing the dev environment sleep/wake cycle through YAML workflows can be complex. This script provides:
- **Simple manual control** - No automation scheduling, just run when you need it
- **Clear cost visibility** - See estimated savings before/after operations
- **Safe operations** - Requires confirmation before making changes
- **Multiple interfaces** - Use interactive menu or direct CLI commands
- **Resource status** - Quick view of what's running and what's not

## What Gets Controlled

### ECS Service
- **Scaling behavior**: Scales desired task count from 0 (stopped) to 2 (running)
- **Cost saved**: ~$0.035/hour when stopped
- **Startup time**: ~30-60 seconds

### RDS Database
- **Stop behavior**: Database enters "stopped" state (backups still retained)
- **Cost saved**: ~$0.038/hour when stopped  
- **Startup time**: ~1-2 minutes
- **Important**: Requires 7 consecutive days of being stopped before AWS deletes it

### NAT Gateway (Advanced)
- **Always active**: Charges continue ($0.045/hour) even when ECS/RDS are stopped
- **Purpose**: Enables private subnets (RDS) to communicate with the internet
- **Can be deleted**: To save money during long idle periods
- **Deletion impact**: Private RDS loses outbound internet access
- **Restoration**: Via Terraform (5 minutes to recreate)
- **Cost saved**: ~$32.85/month if deleted

### Load Balancer (ALB)
- **Always active**: Charges continue ($0.016/hour) even when ECS is stopped
- **Purpose**: Routes incoming traffic to ECS tasks
- **Can be deleted**: Only when ECS service is fully stopped
- **Deletion impact**: External access to application unavailable
- **Restoration**: Via Terraform (5 minutes to recreate)
- **Cost saved**: ~$11.68/month if deleted

### Total Potential Savings
- **Basic (Stop ECS + RDS)**: $73/hour → $53/month saved
- **Aggressive (+ Delete NAT + ALB)**: $134/hour → $98/month saved

## Installation & Setup

### Prerequisites
- AWS CLI v2 installed and configured
- Valid AWS credentials with permissions for:
  - `ecs:UpdateService`
  - `ecs:DescribeServices`
  - `rds:StartDBInstance`
  - `rds:StopDBInstance`
  - `rds:DescribeDBInstances`

### Configuration

The script reads configuration from hardcoded values (can be customized):

```bash
PROJECT_NAME="enterprise-platform"
ENVIRONMENT="dev"
AWS_REGION="eu-north-1"
CLUSTER_NAME="enterprise-platform-dev-cluster"
SERVICE_NAME="enterprise-platform-dev-service"
DB_INSTANCE_ID="enterprise-platform-dev-db"
DEFAULT_TASK_COUNT=2
```

**To customize**, edit the variables at the top of the script:

```bash
nano scripts/resource-control.sh
# Edit variables in section "Configuration from terraform.tfvars"
```

### Usage

#### Interactive Menu (Default)
```bash
./scripts/resource-control.sh
```

This opens an interactive menu where you can:
- View resource status
- Start/stop individual services
- Start/stop all resources at once
- View cost savings estimates

**Menu Options:**
```
1) Start all resources (ECS + RDS)
2) Stop all resources (ECS + RDS)
3) Start ECS service only
4) Stop ECS service only
5) Check ECS service status
6) Start RDS database only
7) Stop RDS database only
8) Check RDS status
9) Check all resources status
10) View estimated cost savings
0) Exit
```

#### Command Line Usage

**Start all resources:**
```bash
./scripts/resource-control.sh start
```

**Stop all resources:**
```bash
./scripts/resource-control.sh stop
```

**Start/Stop individual services:**
```bash
./scripts/resource-control.sh start-ecs     # Start ECS only
./scripts/resource-control.sh stop-ecs      # Stop ECS only
./scripts/resource-control.sh start-rds     # Start RDS only
./scripts/resource-control.sh stop-rds      # Stop RDS only
```

**Advanced - NAT Gateway:**
```bash
./scripts/resource-control.sh delete-nat    # Delete NAT Gateway (save $32.85/month)
./scripts/resource-control.sh recreate-nat  # Recreate NAT Gateway
```

**Advanced - Load Balancer:**
```bash
./scripts/resource-control.sh delete-alb    # Delete ALB (save $11.68/month)
./scripts/resource-control.sh recreate-alb  # Recreate ALB via Terraform
```

**Status commands:**
```bash
./scripts/resource-control.sh status        # Check all resources
./scripts/resource-control.sh cost          # View cost savings breakdown
./scripts/resource-control.sh cost-details  # View detailed cost analysis
```

**Help:**
```bash
./scripts/resource-control.sh help
```

## Workflow Examples

### Morning: Start Dev Environment
```bash
$ ./scripts/resource-control.sh start
# RDS starts first (1-2 min)
# Then ECS service scales up (30-60 sec)
# Application available
```

### Evening: Stop Dev Environment
```bash
$ ./scripts/resource-control.sh stop
# ECS service scales to 0 (immediate)
# RDS database stops (30-60 sec)
# Saving ~$0.073/hour
```

### Aggressive Cost Optimization (Weekend Mode)
```bash
# Option 1: Quick stop (saves $73/month)
$ ./scripts/resource-control.sh stop

# Option 2: Maximum savings - delete NAT + ALB (saves $98/month)
$ ./scripts/resource-control.sh stop          # Stop ECS + RDS
$ ./scripts/resource-control.sh delete-nat    # Save $32.85/month
$ ./scripts/resource-control.sh delete-alb    # Save $11.68/month

# Total saved: ~$98/month on infrastructure that's not in use

# Monday morning to resume (requires Terraform in terraform/ directory)
$ ./scripts/resource-control.sh recreate-nat  # 3-5 minutes
$ ./scripts/resource-control.sh recreate-alb  # 3-5 minutes
$ ./scripts/resource-control.sh start         # Start ECS + RDS
# Total startup time: ~10 minutes
```

### NAT Gateway Advanced Control
```bash
# Save NAT Gateway costs ($32.85/month)
$ ./scripts/resource-control.sh delete-nat

# Implications:
# ✓ Elastic IP deallocates (no charge)
# ✗ RDS loses outbound internet access
# ✗ Package manager updates will fail
# ✓ Backups still work (use internal S3 network)
# ✓ DNS resolution fails (use AWS Route53)

# Only use if you:
# • Don't need to patch RDS OS
# • Control all RDS operations manually
# • Plan to recreate it within 7 days (before it auto-deletes)

# Restore NAT Gateway
$ ./scripts/resource-control.sh recreate-nat
```

### Load Balancer Advanced Control
```bash
# Save ALB costs ($11.68/month)
# CRITICAL: Only delete when ECS is fully stopped

$ ./scripts/resource-control.sh stop          # Must stop ECS first
$ ./scripts/resource-control.sh delete-alb    # Then delete ALB

# Implications:
# ✗ DNS name becomes unavailable
# ✗ Application is unreachable from the internet
# ✓ Quick to recreate (5 minutes via Terraform)

# Restore ALB
$ ./scripts/resource-control.sh recreate-alb
```

### Cost Comparison Scenarios

**Scenario 1: Only weekday usage (8am-6pm, 5 days/week)**
- Weekly stop/start cycles: $0/extra (just scale operations)
- Monthly savings: ~$53 (RDS + ECS downtime)
- Implementation: Simple - use `stop` at 6pm, `start` at 8am

**Scenario 2: Weekday usage + weekend stop (deleted)**
- Delete NAT + ALB on Friday, recreate Monday
- Monthly savings: ~$73 base + ~$20 weekend = ~$93
- Implementation: Medium - requires Terraform recreation

**Scenario 3: Deleted during entire month (except dev work)**
- Delete all, recreate only when needed
- Monthly savings: ~$98 (full infrastructure)
- Implementation: Complex - need careful coordination

### Quick Status Check
```bash
$ ./scripts/resource-control.sh status

╔════════════════════════════════════════════════════════════╗
║ CURRENT RESOURCE STATUS
╚════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━ ECS SERVICE ━━━━━━━━━━━━
serviceName                          status    desiredCount    runningCount    pendingCount
-------                              ------    -----------     -----------     -----------
enterprise-platform-dev-service      ACTIVE    2               2               0

━━━━━━━━━━━━ RDS DATABASE ━━━━━━━━━━━━
DBInstanceIdentifier             DBInstanceStatus    DBInstanceClass
----------------------------     ----------------    ---------------
enterprise-platform-dev-db       available           db.t3.micro
```

## Safety & Confirmations

All operations that modify state require explicit confirmation:

```
This will scale down the ECS service to 0 tasks and stop all running containers
Do you want to stop the ECS service? (yes/no): 
```

**You must type "yes" or "no"** - simply pressing Enter won't work.

This prevents accidental operations.

## Understanding Infrastructure Costs

### Why NAT Gateway Costs Continue When ECS is Stopped

The NAT Gateway ($0.045/hour) and ALB ($0.016/hour) continue charging even when your ECS service is stopped because:

1. **NAT Gateway is Infrastructure**: It's part of your VPC networking, not tied to ECS
   - Enables private RDS to access the internet for updates/patches
   - Processes data transfer charges ($0.032/GB outbound)
   - Cannot be "paused" - only deleted or kept running

2. **ALB is Infrastructure**: It's a network resource, not an application resource  
   - Provides load balancing for incoming traffic
   - Allocates resources across availability zones
   - Cannot be "paused" - only deleted or kept running

### Cost Breakdown Table

| Resource | Hourly | Monthly | Type | Stoppable? | Can Delete? |
|----------|--------|---------|------|-----------|------------|
| ECS Tasks (2×256) | $0.035 | $25.55 | Compute | ✅ Scale to 0 | N/A |
| RDS db.t3.micro | $0.038 | $27.74 | Database | ✅ Stop | ⚠️ 7-day hold |
| NAT Gateway | $0.045 | $32.85 | Network | ❌ Always on | ✅ Via Terraform |
| Load Balancer | $0.016 | $11.68 | Network | ❌ Always on | ✅ Via Terraform |
| VPC & Networking | $0.00 | ~$0.05 | Infrastructure | N/A | N/A |
| **TOTAL** | **$0.134** | **$97.87** | | | |

### Deletion Implications

**Deleting NAT Gateway:**
- ✅ Stops all hourly charges ($0.045/hour)
- ❌ Elastic IP deallocates (good - no charge)
- ❌ Private RDS loses outbound internet access
- ⚠️ Impacts: OS patches, package updates, external API calls
- ⏱️ Recreate time: 3-5 minutes (Terraform)
- 💾 Requires: Terraform with networking module

**Deleting Load Balancer:**
- ✅ Stops all hourly charges ($0.016/hour)
- ❌ DNS name becomes unavailable
- ❌ Application unreachable from internet
- ✅ Only safe when ECS is fully stopped
- ⏱️ Recreate time: 5 minutes (Terraform)
- 💾 Requires: Terraform with ALB module

## Troubleshooting

### "AWS credentials not configured or invalid"
- Verify AWS credentials: `aws sts get-caller-identity`
- Check IAM permissions for the operations listed above

### "ECS Service not found"
- Verify cluster and service names
- Check that your dev environment is created: `aws ecs list-clusters --region eu-north-1`

### "RDS Instance not found"
- Verify RDS instance ID
- Check: `aws rds describe-db-instances --region eu-north-1`

### RDS Takes Long Time to Start
- This is normal - RDS can take 1-2 minutes to start
- Monitor in AWS Console: RDS → Databases → enterprise-platform-dev-db

### ECS Tasks Don't Start After RDS Starts
- Check ECS service logs: `aws logs tail /ecs/enterprise-platform-dev --follow`
- Verify RDS is actually available (not just in "started" state)
- Check network/security group connectivity

### "NAT Gateway not found"
- NAT Gateway may already be deleted
- Check AWS Console: VPC → NAT Gateways
- Verify tag name matches: `${PROJECT_NAME}-${ENVIRONMENT}-nat`

### "Terraform not found" when recreating NAT/ALB
- Ensure you're in the project root directory
- Check terraform/ subdirectory exists: `ls -la terraform/`
- Verify Terraform is installed: `terraform --version`
- Check AWS credentials are configured

### NAT Gateway fails to delete
- Cannot delete if still in use by route tables
- Check route tables: `aws ec2 describe-route-tables --region eu-north-1`
- May need to manually update routes in AWS Console

### ALB fails to delete (ECS still attached)
- Error: "This alb has target groups attached"
- Solution: Run `./scripts/resource-control.sh stop` first
- Verify no running ECS tasks: `./scripts/resource-control.sh status`

### Terraform apply fails during NAT recreation
- Common: "InvalidParameterValue.NotFound" for Elastic IP
- Solution: EIP may still be deallocating (wait 30 seconds, retry)
- Manual fix: `aws ec2 allocate-address --domain vpc --region eu-north-1`

### RDS loses connectivity after NAT deletion
- Expected behavior - private RDS has no outbound access
- Backups still work (AWS internal network)
- To restore: `./scripts/resource-control.sh recreate-nat`

### Data Processing Charges for NAT Gateway
When NAT is running, you may see data processing charges:
- Outbound data: $0.032/GB (data leaving AWS)
- Inbound data: Free
- Monitor: Use CloudWatch → NAT Gateways → BytesOutToDestination
- Optimization: Use VPC Endpoints for AWS services (DynamoDB, S3, etc.)

## Cost Tracking

The script provides estimated hourly and monthly savings:

```
╔════════════════════════════════════════════════════════════╗
║ ESTIMATED COST SAVINGS
╚════════════════════════════════════════════════════════════╝

Hourly Cost Estimates (Approximate):
  • ECS Fargate (2 tasks, 256 CPU, 512 MB): ~$0.035/hour
  • RDS db.t3.micro (Multi-AZ): ~$0.038/hour
  • NAT Gateway: ~$0.045/hour
  • Load Balancer: ~$0.016/hour

Total running resources: ~$0.134/hour
Stopped (ECS + RDS): ~$0.073/hour saved

Monthly savings (24/7 operation): ~$53 (50% reduction)
```

**Notes:**
- NAT Gateway and Load Balancer charges continue even when services are stopped
- These are estimated costs based on 2026 pricing in eu-north-1
- For actual costs, check AWS Billing Dashboard
- Multi-AZ RDS increases costs but improves availability

## Comparison with Automation Workflows

| Feature | resource-control.sh | Cron/YAML Automation |
|---------|-------------------|-------------------|
| Setup complexity | Low | High |
| Configuration drift | Low | Medium |
| Manual override | Yes | Requires code change |
| Scheduling | Manual | Automatic |
| Cost visibility | Built-in | Manual tracking |
| Error messages | Clear | Workflow logs |
| Testing/debugging | Easy | Complex |

**Choose this script if:**
- Dev environment is not 24/7 (manual use patterns)
- You prefer predictable, controllable operations
- Setup simplicity is important
- Your team is small and can coordinate manually

## Next Steps

### Option 1: Enhanced Automation (If Needed Later)
If you want scheduled operations without complex workflows, you can:
```bash
# Add to crontab for automatic operations
0 18 * * MON-FRI /home/silentkn1ght/projects/enterprise-platform/scripts/resource-control.sh stop    # Stop at 6pm weekdays
0 8 * * MON-FRI /home/silentkn1ght/projects/enterprise-platform/scripts/resource-control.sh start    # Start at 8am weekdays
```

### Option 2: Team Notification
Notify team when resources are stopped:
```bash
./scripts/resource-control.sh stop && \
  aws sns publish --topic-arn arn:aws:sns:eu-north-1:xxx:dev-alerts \
    --message "Dev environment stopped. Restarting env: resource-control.sh start"
```

### Option 3: Add More Resources
Edit the script to control additional resources:
- ElastiCache clusters
- DocumentDB instances
- Lambda functions (cold starts)
- DMS replication instances

## Support & Issues

If you encounter issues:

1. **Check resource status:**
   ```bash
   ./scripts/resource-control.sh status
   ```

2. **Review AWS Console:**
   - ECS: https://console.aws.amazon.com/ecs/
   - RDS: https://console.aws.amazon.com/rds/

3. **Check AWS credentials:**
   ```bash
   aws sts get-caller-identity
   ```

4. **Review script logs** (add debug output):
   ```bash
   bash -x ./scripts/resource-control.sh start 2>&1 | tee debug.log
   ```

## Script Features

✅ **Interactive menu** with 10+ options  
✅ **Safe operations** with explicit confirmation  
✅ **Status monitoring** built-in  
✅ **Cost visibility** with savings estimates  
✅ **Color-coded output** for easy reading  
✅ **Error handling** with helpful messages  
✅ **Multiple interfaces** (menu + CLI)  
✅ **No external dependencies** (bash + AWS CLI only)  
✅ **Parallel execution** (RDS first, then ECS for start)  
✅ **Sequential shutdown** (ECS first, then RDS)  

---

**Created**: 2026-03-04  
**Technology**: Bash + AWS CLI  
**Status**: Production Ready  
**Maintenance**: Low - only needs AWS credential validation
