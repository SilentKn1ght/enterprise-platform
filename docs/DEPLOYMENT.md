# Deployment Guide

**Last Updated:** March 8, 2026  
**Target Environment:** AWS (eu-north-1)  
**Deployment Method:** Terraform + GitHub Actions

---

## Prerequisites

### Tools You'll Need

Before deploying, make sure you have these installed:

```bash
# Check if installed
aws --version          # AWS CLI v2+
terraform --version    # Terraform 1.0+
docker --version       # Docker 20.10+
git --version          # Git 2.0+
```

**Installation links:**
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- [Docker](https://docs.docker.com/get-docker/)
- [Git](https://git-scm.com/downloads)

### AWS Account Setup

You'll need:

1. **AWS Account** with admin access (or IAM user with these permissions):
   - EC2 (VPC, Security Groups, ALB)
   - ECS (Fargate, Services)
   - RDS (Database instances)
   - ECR (Container registry)
   - CloudWatch (Logs and metrics)
   - IAM (Roles and policies)
   - Secrets Manager
   - Terraform state storage (optional S3 backend)

2. **AWS Credentials Configured:**
   ```bash
   aws configure
   # Enter your AWS Access Key ID
   # Enter your AWS Secret Access Key
   # Enter region: eu-north-1
   # Enter output format: json
   ```

3. **AWS Region:** eu-north-1 (Stockholm)
   - Change in terraform.tfvars if needed

---

## Phase 1: Initial Setup (First Time Only)

### Step 1: Clone the Repository

```bash
git clone https://github.com/SilentKn1ght/enterprise-platform.git
cd enterprise-platform
```

### Step 2: Build and Push Docker Image

Before deploying infrastructure, you need to push your application's Docker image to Amazon's container registry (ECR).

```bash
# Navigate to the API service
cd services/api

# Build the Docker image
docker build -t enterprise-platform:latest .

# Expected output:
# Step 1/X : FROM node:18-alpine
# ...
# Successfully built [IMAGE_ID]
```

**Create ECR Repository:**

```bash
aws ecr create-repository \
  --repository-name enterprise-platform \
  --region eu-north-1
```

**Output:** Note the repository URI (you'll need this in terraform.tfvars)

```json
{
  "repository": {
    "repositoryUri": "[ACCOUNT_ID].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform"
  }
}
```

**Push Image to ECR:**

```bash
# Get login credentials
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin \
  [ACCOUNT_ID].dkr.ecr.eu-north-1.amazonaws.com

# Tag the image with your ECR repository
docker tag enterprise-platform:latest \
  [ACCOUNT_ID].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:latest

# Push the image
docker push [ACCOUNT_ID].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:latest

# Verify
aws ecr describe-images \
  --repository-name enterprise-platform \
  --region eu-north-1
```

### Step 3: Configure Terraform Variables

```bash
cd ../../terraform

# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars 2>/dev/null || cat > terraform.tfvars << 'EOF'
aws_region    = "eu-north-1"
project_name  = "enterprise-platform"
environment   = "development"

# Your ECR image URI from Step 2
ecr_image_uri = "[ACCOUNT_ID].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:latest"

# Database credentials (change these!)
db_username   = "enterprise_admin"
db_password   = "YourSecurePassword123!@#"

# Auto-scaling configuration
min_capacity  = 2
max_capacity  = 6

# Network configuration
availability_zones = ["eu-north-1a", "eu-north-1b"]
EOF

# Edit with your actual values
nano terraform.tfvars
```

**Critical variables:**

| Variable | Required | Example |
|----------|----------|---------|
| `ecr_image_uri` | Yes | `[ACCOUNT].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:latest` |
| `db_username` | Yes | `enterprise_admin` |
| `db_password` | Yes | `SecurePassword123!@#` (min 12 chars) |
| `aws_region` | No | `eu-north-1` (default) |
| `project_name` | No | `enterprise-platform` (default) |

### Step 4: Initialize Terraform

This downloads AWS provider plugins and prepares Terraform:

```bash
terraform init
```

**Expected output:**
```
Terraform has been successfully configured!

You may now begin working with Terraform. Try running "terraform plan" next.
```

**If it fails:**
- Check AWS credentials: `aws sts get-caller-identity`
- Check internet connection
- Check terraform.tfvars syntax: `terraform validate`

### Step 5: Review the Deployment Plan

Always review what Terraform will create before applying:

```bash
terraform plan -out=tfplan
```

**Output summary:**
- Shows all resources that will be created
- Tells you if values are correct
- Takes 30-60 seconds

**Look for:**
- ALB, ECS cluster, ECS service
- RDS instance
- VPC, subnets, security groups
- IAM roles

### Step 6: Apply the Infrastructure

This creates all AWS resources. First deployment takes 15-30 minutes:

```bash
terraform apply tfplan
```

**Expected output:**
```
Apply complete! Resources created: 47

Outputs:
alb_dns_name = "enterprise-platform-alb-1234567890.eu-north-1.elb.amazonaws.com"
```

**While it's deploying, you can monitor in AWS Console:**
- ECS: https://console.aws.amazon.com/ecs
- RDS: https://console.aws.amazon.com/rds
- ALB: https://console.aws.amazon.com/ec2/v2/home#LoadBalancers

### Step 7: Verify the Deployment

Once Terraform completes, test that everything works:

```bash
# Get the ALB DNS name
ALB=$(terraform output -raw alb_dns_name)

# Test the health endpoint
curl http://$ALB/health

# Expected response:
# {"status":"healthy","timestamp":"2026-03-08T..."}

# Try the API
curl http://$ALB/api
curl http://$ALB/api/status
```

**Troubleshooting:**
- If no response: Wait 2 minutes (ECS tasks still starting)
- If 503 error: Check ECS tasks are running in AWS Console
- If timeout: Check security groups allow port 80

---

## Phase 2: Deploy Application Updates

### Method 1: Automatic (Recommended)

After initial setup, new code deploys automatically:

```bash
# Make changes to your code
nano services/api/app.js

# Commit and push to main
git add .
git commit -m "Update API endpoint"
git push origin main

# GitHub Actions automatically:
# 1. Runs tests
# 2. Builds new Docker image
# 3. Pushes to ECR
# 4. Updates ECS service
# 5. Rolling deployment (30-60 seconds)
```

**Monitor deployment:**
```bash
# Watch ECS service deployments in AWS Console
# https://console.aws.amazon.com/ecs

# Or via CLI:
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1 \
  --query 'services[0].deployments'
```

### Method 2: Manual Update

For emergency updates or testing:

```bash
# Build and push new image
cd services/api
docker build -t enterprise-platform:v1.0.1 .

docker push [ACCOUNT].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:v1.0.1

# Update ECS to use new image
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1

# Wait for deployment (check status)
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1
```

---

## Phase 3: Infrastructure Updates

### Update Terraform Configuration

When you need to change infrastructure (not code):

```bash
cd terraform

# Edit the configuration
nano terraform/variables.tf
# Or terraform.tfvars

# Review what will change
terraform plan

# Apply the changes
terraform apply
```

**Common infrastructure changes:**

**1. Scale ECS tasks:**
```hcl
# In terraform.tfvars
min_capacity = 4  # was 2
max_capacity = 10  # was 6
```

**2. Resize database:**
```hcl
# In terraform.tfvars
db_instance_class = "db.t3.small"  # was db.t3.micro
# Warning: causes brief downtime
```

**3. Add environment variable:**
```hcl
# In terraform/modules/ecs/main.tf
environment = [
  {
    name  = "NEW_VAR"
    value = "value"
  }
]
```

**4. Update container image:**
```hcl
# In terraform.tfvars
ecr_image_uri = "[ACCOUNT].dkr.ecr.eu-north-1.amazonaws.com/enterprise-platform:v1.0.1"
```

---

## Phase 4: Production Deployment

Not recommended until Day 35, but here's what you'd do differently:

```hcl
# In terraform.tfvars (production)
environment      = "production"
min_capacity     = 4          # higher baseline
max_capacity     = 20         # more capacity
db_instance_class = "db.t3.small"  # larger database
enable_multi_az  = true       # redundancy
enable_https     = true       # SSL/TLS
```

---

## Rollback Procedures

### Rollback Application Code

If new code breaks something:

```bash
# Revert the commit
git revert HEAD
git push origin main

# GitHub Actions automatically redeploys previous version
# Time: ~2 minutes

# Or manually update ECS to previous image
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --task-definition enterprise-platform-dev:PREVIOUS_REVISION \
  --region eu-north-1
```

### Rollback Infrastructure

If Terraform changes cause issues:

```bash
cd terraform

# Revert the change
git revert HEAD
git push origin main

# Re-apply
terraform apply

# Or manually restore from Git:
git checkout previous-commit -- terraform/
terraform apply
```

### Restore Database

If database is corrupted:

```bash
# List available backups
aws rds describe-db-snapshots \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1

# Restore from snapshot (creates new instance)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier enterprise-platform-db-restored \
  --db-snapshot-identifier [SNAPSHOT_ID] \
  --region eu-north-1

# Update ECS to point to new database endpoint
# (Requires Terraform changes + redeployment)
```

---

## Disaster Recovery

### Backup Database

Automated daily backups are created, but you can also:

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier enterprise-platform-db \
  --db-snapshot-identifier enterprise-platform-backup-$(date +%s) \
  --region eu-north-1

# List snapshots
aws rds describe-db-snapshots --region eu-north-1
```

### Export Terraform State

Keep your Terraform state safe:

```bash
# Local backup
cp terraform/terraform.tfstate terraform/terraform.tfstate.backup

# Remote backend (optional, recommended for production)
# Add to terraform/variables.tf:
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "enterprise-platform/terraform.tfstate"
    region = "eu-north-1"
  }
}

terraform init  # Migrate state to S3
```

---

## Monitoring Deployments

### CloudWatch Logs

See what's happening in your application:

```bash
# View recent logs
aws logs tail /ecs/enterprise-platform-dev \
  --follow \
  --region eu-north-1

# Search for errors
aws logs filter-log-events \
  --log-group-name /ecs/enterprise-platform-dev \
  --filter-pattern "ERROR" \
  --region eu-north-1
```

### ECS Events

Track container lifecycle:

```bash
# View service events
aws ecs describe-services \
  --cluster enterprise-platform-dev-cluster \
  --services enterprise-platform-dev-service \
  --region eu-north-1 \
  --query 'services[0].events'
```

### Metrics

Check CPU, memory, and request counts:

In **AWS Console:**
1. Services → ECS → Clusters → enterprise-platform-dev-cluster
2. Services → enterprise-platform-dev-service
3. View metrics in CloudWatch

**Or via CLI:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=enterprise-platform-dev-service \
  --statistics Average \
  --start-time 2026-03-08T00:00:00Z \
  --end-time 2026-03-08T23:59:59Z \
  --period 3600 \
  --region eu-north-1
```

---

## Cost Monitoring

### Check Current Spending

```bash
# Get month-to-date costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '1 month ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=SERVICE

# Get forecast for this month
aws ce get-cost-forecast \
  --time-period Start=$(date -u +%Y-%m-%d),End=$(date -u -d '30 days' +%Y-%m-%d) \
  --metric UNBLENDED_COST \
  --granularity MONTHLY
```

---

## Cleanup (Destroy Resources)

When you're ready to stop (and stop paying):

```bash
cd terraform

# See what will be deleted
terraform plan -destroy

# Delete everything
terraform destroy

# Confirm with: yes

# Note: RDS snapshots are retained
# Delete them manually in AWS Console if needed
```

---

## Common Issues & Solutions

### "InvalidParameterException: Invalid task definition"

**Cause:** ECR image URI is wrong or image doesn't exist

**Solution:**
```bash
# Check image exists
aws ecr describe-images \
  --repository-name enterprise-platform \
  --region eu-north-1

# Update terraform.tfvars with correct URI
```

### "Service is unable to continuously place tasks"

**Cause:** ECS task definition is invalid or account limits exceeded

**Solution:**
```bash
# Check task definition
aws ecs describe-task-definition \
  --task-definition enterprise-platform-dev \
  --region eu-north-1

# Check limits
aws service-quotas list-service-quotas \
  --service-code ecs

# May need larger task size
```

### "Database connection refused"

**Cause:** RDS not ready yet, or security group misconfigured

**Solution:**
```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier enterprise-platform-db \
  --region eu-north-1 | grep DBInstanceStatus

# Wait if status is "creating" or "modifying"
# Check security group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=enterprise-platform*rds*" \
  --region eu-north-1
```

### "ALB target is unhealthy"

**Cause:** ECS task failing health checks

**Solution:**
```bash
# Check task logs
aws logs tail /ecs/enterprise-platform-dev --follow --region eu-north-1

# Check health endpoint
curl http://[ALB_DNS]/health -v

# Restart service
aws ecs update-service \
  --cluster enterprise-platform-dev-cluster \
  --service enterprise-platform-dev-service \
  --force-new-deployment \
  --region eu-north-1
```

---

## Next Steps

After deployment, see:
- [OPERATIONS.md](OPERATIONS.md) - How to operate the system
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Fixing common problems
- [ARCHITECTURE.md](ARCHITECTURE.md) - Understanding the system design
- [Load-Testing-Guide.md](Load-Testing-Guide.md) - Performance testing
