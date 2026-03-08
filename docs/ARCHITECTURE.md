# Enterprise Platform Architecture

**Version:** 1.0.0  
**Last Updated:** March 8, 2026  
**Environment:** AWS (eu-north-1)

---

## Quick Overview

Enterprise Platform is a production-grade Node.js REST API running on AWS. It demonstrates modern DevOps practices: Infrastructure as Code, containerization, monitoring, and security hardening. The system automatically scales based on demand and includes comprehensive logging and alerting.

**Key Components:**
- **Frontend:** Simple HTML dashboard  
- **API:** Node.js Express server running on ECS Fargate  
- **Database:** PostgreSQL 15.4 on RDS  
- **Load Balancer:** AWS Application Load Balancer  
- **Monitoring:** Prometheus, Grafana, and Loki stack  

---

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Internet (Users)                              │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTP/HTTPS
                         ▼
        ┌────────────────────────────────────┐
        │   AWS Route 53 (DNS)               │
        │   enterprise-platform.com          │
        └────────────┬───────────────────────┘
                     │
                     ▼
        ┌────────────────────────────────────┐
        │  AWS Public Subnets (us-east-1a/b) │
        │  ┌──────────────────────────────┐  │
        │  │  Application Load Balancer   │  │
        │  │  Port 80/443                 │  │
        │  └────────────┬─────────────────┘  │
        └─────────────────┬──────────────────┘
                          │ Forward traffic
        ┌─────────────────┼──────────────────┐
        │ AWS VPC 10.0.0.0/16               │
        │                 │                  │
        │    ┌────────────▼────────────┐    │
        │    │  Private Subnets        │    │
        │    │  (10.0.100-101/24)      │    │
        │    │                         │    │
        │    │ ┌──────────────────┐   │    │
        │    │ │ ECS Fargate      │   │    │
        │    │ │ (2-6 tasks)      │   │    │
        │    │ │ Node.js API      │   │    │
        │    │ │ Port 3000        │   │    │
        │    │ └────────┬─────────┘   │    │
        │    │          │              │    │
        │    │ ┌────────▼─────────┐   │    │
        │    │ │   RDS           │   │    │
        │    │ │   PostgreSQL    │   │    │
        │    │ │   port 5432     │   │    │
        │    │ └─────────────────┘   │    │
        │    └─────────────────────────┘    │
        │                                    │
        │    ┌────────────────────────────┐ │
        │    │  NAT Gateway               │ │
        │    │  (Private → Internet)      │ │
        │    └────────────────────────────┘ │
        └────────────────────────────────────┘
                         │
        ┌────────────────▼───────────────────┐
        │  External Services                  │
        │  - ECR (container registry)         │
        │  - Secrets Manager (credentials)   │
        │  - CloudWatch (logs & metrics)     │
        └────────────────────────────────────┘
```

---

## Network Architecture

### VPC Configuration

- **CIDR Block:** 10.0.0.0/16 (65,536 IP addresses)
- **Availability Zones:** 2 (us-east-1a, us-east-1b for redundancy)
- **Subnets:** 4 total (2 public, 2 private)

### Subnet Breakdown

| Subnet | CIDR | Type | Zone | Purpose |
|--------|------|------|------|---------|
| Public-1a | 10.0.1.0/24 | Public | us-east-1a | ALB, NAT Gateway |
| Public-1b | 10.0.2.0/24 | Public | us-east-1b | ALB, NAT Gateway |
| Private-1a | 10.0.100.0/24 | Private | us-east-1a | ECS tasks, RDS |
| Private-1b | 10.0.101.0/24 | Private | us-east-1b | ECS tasks, RDS |

### Traffic Flow

1. **Inbound:** Internet → ALB → ECS Tasks (port 3000) via load balancing
2. **Database:** ECS Tasks → RDS (port 5432) via private network
3. **Outbound:** ECS/RDS → NAT Gateway → Internet Gateway → Internet

---

## Compute Layer (ECS Fargate)

### What is ECS Fargate?

Think of ECS Fargate as a managed container service where AWS handles the server infrastructure. You just specify what Docker container to run, how much CPU/memory it needs, and AWS takes care of the rest—scaling up and down based on demand.

### Task Configuration

| Setting | Value | Reason |
|---------|-------|--------|
| **CPU** | 0.25 vCPU (256 units) | Cost-optimized for development |
| **Memory** | 512 MB | Minimum viable for Node.js app |
| **Image** | Docker image from ECR | Container registry storage |
| **Port** | 3000 | Node.js Express server port |
| **Network Mode** | awsvpc | Required for Fargate, provides ENI |

### Health Check

```
GET /health → 200 OK
Every 30 seconds
Healthy after: 2 consecutive successes
Unhealthy after: 3 consecutive failures
```

The health check prevents traffic from being sent to failing containers. If 3 checks fail, the container is automatically replaced.

### Auto-Scaling Policy

The service automatically adjusts the number of running tasks:

| Metric | Threshold | Action | Cooldown |
|--------|-----------|--------|----------|
| **CPU** | > 70% for 5 min | Scale out (+1 task) | 60 sec |
| **CPU** | < 30% for 10 min | Scale in (-1 task) | 300 sec |
| **Memory** | > 80% for 5 min | Scale out (+1 task) | 60 sec |

**Limits:** 1-6 tasks (configurable in terraform.tfvars)

---

## Database Layer (RDS PostgreSQL)

### Instance Details

| Property | Value |
|----------|-------|
| **Engine** | PostgreSQL 15.4 |
| **Instance Class** | db.t3.micro |
| **Storage** | 20 GB gp3 (auto-scaling up to 40 GB) |
| **Multi-AZ** | No (development environment) |
| **Public Access** | No (private subnet only) |

### Security Features

✅ **Enabled:**
- Encryption at rest (AWS KMS)
- SSL/TLS enforcement for connections
- Private subnet only (no direct internet access)
- Restricted security group (ECS tasks only)
- Backup encryption
- Enhanced monitoring

### Backup Strategy

- **Automatic Backups:** Daily at 03:00 UTC
- **Retention Period:** 7 days
- **Manual Snapshots:** Before major changes or releases
- **Recovery:** Can restore to any point within 7-day window

### Connection Management

- **Max Connections:** ~200 (db.t3.micro limit)
- **Current Usage:** ~5-10 (2-6 ECS tasks)
- **Timeout:** 5 minutes of inactivity
- **Lazy Connections:** PostgreSQL closes idle connections

---

## Load Balancer (Application Load Balancer)

### What is an ALB?

An ALB is AWS's smart load balancer. It distributes incoming HTTP traffic across your ECS tasks. If you have 3 tasks running, requests are automatically split between them.

### Configuration

| Setting | Value |
|---------|-------|
| **Type** | Application Load Balancer (ALB) |
| **Scheme** | Internet-facing (public) |
| **Port** | 80 (HTTP), 443 (HTTPS optional) |
| **Protocol** | HTTP/1.1, HTTP/2 capable |
| **Target Group** | ECS tasks on port 3000 |
| **Cross-Zone** | Enabled (balances across AZs) |

### Health Check

```
Target: ECS task on port 3000
Endpoint: GET /health
Interval: 30 seconds
Success codes: 200-299
Timeout: 5 seconds
Healthy threshold: 2 consecutive successes
Unhealthy threshold: 2 consecutive failures
```

Failed health checks trigger automatic deregistration. The task either recovers or is replaced by auto-scaling.

### Features

- **Sticky Sessions:** Disabled (stateless API)
- **Request Logging:** Optional (logs to S3)
- **WebSocket Support:** Available if needed
- **Keep-Alive:** Enabled (improves latency)

---

## Monitoring & Observability

### CloudWatch (AWS Native Monitoring)

**Metrics Collected:**

| Component | Metrics |
|-----------|---------|
| **ECS Tasks** | CPU %, Memory %, Restart count, Task count |
| **RDS** | CPU %, Connections, Disk space, Read/Write latency |
| **ALB** | Request count, Response time, HTTP status codes |
| **VPC** | Data transferred in/out |

**Alarms:** 
- ECS CPU > 80% → Auto-scale out
- RDS storage < 2 GB free → Alert
- ALB unhealthy targets > 0 → Alert

### Prometheus + Grafana (Custom Monitoring)

The application exposes Prometheus metrics at `/metrics` endpoint:

```
GET /metrics → Prometheus text format
```

**Key Metrics:**
- `http_requests_total` - Total HTTP requests
- `http_request_duration_seconds` - Request latency histogram
- `active_connections` - Current connections
- `process_resident_memory_bytes` - Application memory usage

**Dashboards:**
- Application Overview
- System Metrics
- HTTP Performance
- Alerts Overview

### Loki (Log Aggregation)

All ECS logs are sent to CloudWatch Logs, then queried via Loki:

```
Type: application logs
Source: ECS task containers
Retention: 7 days
Format: JSON + plaintext
```

---

## Security Architecture

### Defense in Depth (Layered Security)

#### Layer 1: Network Architecture
- VPC isolation with public/private subnets
- Security groups acting as stateful firewalls
- NAT Gateway for controlled outbound access
- No direct internet access to databases or internal services

#### Layer 2: Container Security
- Containers run from ECR (centralized registry)
- Image scanning enabled (detects vulnerabilities)
- Non-root user in container
- Read-only root filesystem (optional)

#### Layer 3: Data Protection
- RDS encryption at rest (AES-256)
- TLS/SSL for database connections
- No plaintext credentials in code
- Secrets stored in AWS Secrets Manager

#### Layer 4: Access Control
- IAM roles for ECS tasks (not access keys)
- Least privilege policies
- Secrets Manager for credential rotation
- No hardcoded secrets in Docker images

#### Layer 5: Monitoring
- CloudWatch Logs with audit trail
- CloudTrail for API calls (optional)
- VPC Flow Logs for network monitoring
- GuardDuty for threat detection (optional)

### Security Groups (Firewall Rules)

**ALB Security Group:**
```
Inbound:
  - Port 80 from 0.0.0.0/0 (anyone, anywhere)
  - Port 443 from 0.0.0.0/0 (if HTTPS configured)
Outbound:
  - All traffic (necessary for health checks)
```

**ECS Security Group:**
```
Inbound:
  - Port 3000 from ALB Security Group only
  - (no inbound from internet or RDS)
Outbound:
  - All traffic (for NAT Gateway access)
```

**RDS Security Group:**
```
Inbound:
  - Port 5432 from ECS Security Group only
  - (no internet access)
Outbound:
  - None needed
```

---

## Deployment Pipeline (CI/CD)

### GitHub Actions Workflow

**Trigger:** Push to `main` branch

**Steps:**
1. Checkout code and install dependencies
2. Run unit tests (Jest)
3. Run linting (ESLint)
4. Build Docker image
5. Login to ECR
6. Push image with tag (`:latest` and `:git-sha`)
7. Update ECS service with new image

**Result:** ECS automatically performs rolling deployment (new tasks launched, health checked, old tasks drained)

### Deployment Time: ~2-3 minutes

New code deployed automatically on every push to main branch.

---

## Data Flow Through the System

### Request Flow (User to Database)

```
1. User sends HTTP request
   User → [Internet]

2. ALB receives request
   ALB receives on port 80
   Checks health of ECS tasks
   Picks a healthy task (round-robin)

3. ECS Task processes request
   Node.js app receives on port 3000
   Validates request
   Queries database if needed

4. RDS processes database call
   PostgreSQL executes query
   Returns results to ECS task

5. Response flows back
   ECS task → ALB → User
   Status code + JSON response
```

### Database Backup Flow

```
Daily at 03:00 UTC:
  RDS → Automated Snapshot
  Snapshot → AWS S3 (encrypted)
  Older snapshots (>7 days) → Deleted

Manual Snapshot:
  Engineer → AWS Console/CLI
  Create Snapshot → S3 (encrypted)
  Retained until manually deleted
```

---

## Cost Structure

### Monthly Breakdown (Development Environment)

| Service | Cost | Notes |
|---------|------|-------|
| **ECS Fargate** | €24 | 2 tasks base + auto-scaling |
| **ALB** | €16 | Always running |
| **NAT Gateway** | €32 | Data transfer + instance hours |
| **RDS** | €28 | db.t3.micro on-demand |
| **CloudWatch** | €12 | Logs, metrics, alarms |
| **VPC Endpoints** | €14 | Secrets Manager, ECR |
| **ECR Storage** | €0.50 | Container images |
| **Data Transfer** | €5 | Outbound internet traffic |
| **Misc** | €6 | RDS monitoring, Secrets Manager |
| **TOTAL** | **€140/month** | |

### Cost Optimization Tips

1. **Use Reserved Instances** for RDS (saves ~35%)
2. **Schedule tasks off-hours** (stop dev environment 6pm-9am)
3. **Monitor data transfer** (can be expensive)
4. **Consolidate logs** to 7-day retention instead of 30

---

## Technology Stack

### Infrastructure
- **Cloud:** AWS (eu-north-1 region)
- **IaC:** Terraform 1.0+
- **Container Orchestration:** ECS Fargate (serverless)
- **Load Balancing:** Application Load Balancer

### Application
- **Runtime:** Node.js 18 (Alpine Linux)
- **Framework:** Express.js
- **Database Driver:** node-postgres
- **Build:** Docker multi-stage builds

### Observability
- **Metrics:** AWS CloudWatch + Prometheus
- **Logs:** AWS CloudWatch Logs + Loki
- **Dashboards:** Grafana
- **Alerting:** CloudWatch Alarms + Prometheus Alertmanager

### DevOps
- **Version Control:** Git/GitHub
- **CI/CD:** GitHub Actions
- **Container Registry:** AWS ECR
- **Secrets:** AWS Secrets Manager
- **IaC State:** Terraform state (local + S3 backend ready)

---

## Performance Characteristics

### Baseline Performance (from load testing)

| Metric | Value |
|--------|-------|
| **Throughput** | ~100 req/sec (2 tasks) |
| **Latency p50** | 15 ms |
| **Latency p95** | 45 ms |
| **Latency p99** | 120 ms |
| **Error Rate** | < 0.1% |

### Scaling Behavior

| Task Count | Throughput | Response Time |
|-----------|-----------|----------------|
| 1 task | ~50 req/sec | +50% latency |
| 2 tasks | ~100 req/sec | baseline |
| 4 tasks | ~200 req/sec | -20% latency |
| 6 tasks | ~300 req/sec | -30% latency |

---

## Recovery & Disaster Recovery

### RTO and RPO

- **RTO (Recovery Time Objective):** 1 hour (restore from backup + redeploy)
- **RPO (Recovery Point Objective):** 24 hours (daily backups)

### Failure Scenarios

**ECS Task Fails:**
- Health check fails → ALB stops sending traffic
- Auto-scaling detects mismatch → Launches new task
- Time to recover: ~1 minute

**Database Unavailable:**
- Connection pooling times out → Application returns 503 error
- ALB marks unhealthy → Requests error immediately
- Recovery: Restore from snapshot (manual, ~5 minutes)

**ALB Fails:**
- Managed by AWS (99.99% SLA)
- Automatic failover across AZs (built-in)

**ECS Cluster Critical:**
- Deploy to second region (requires multi-region setup)
- Rolling back to previous version (Terraform remote state)

---

## Future Enhancements

**Planned improvements:**
- HTTPS/TLS termination at ALB
- Route 53 for DNS management + health checks
- ElastiCache (Redis) for session/caching layer
- EventBridge for scheduled tasks
- Multi-region failover
- AWS WAF (Web Application Firewall)
- X-Ray for distributed tracing

---

## Quick Reference: Key Endpoints

```
Application: http://alb-dns/health
EC2 Dashboard: https://console.aws.amazon.com/ec2
ECS Cluster: https://console.aws.amazon.com/ecs
RDS Dashboard: https://console.aws.amazon.com/rds
CloudWatch: https://console.aws.amazon.com/cloudwatch
ECR: https://console.aws.amazon.com/ecr
Grafana: http://grafana.internal:3000
Prometheus: http://prometheus.internal:9090
```

---

## Related Documentation

- [DEPLOYMENT.md](DEPLOYMENT.md) - How to deploy this system
- [OPERATIONS.md](OPERATIONS.md) - How to operate and troubleshoot
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [Load-Testing-Guide.md](Load-Testing-Guide.md) - Performance testing procedures
