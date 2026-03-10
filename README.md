# Enterprise Platform

[![Test & Lint](https://github.com/SilentKn1ght/enterprise-platform/actions/workflows/test.yml/badge.svg)](https://github.com/SilentKn1ght/enterprise-platform/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/SilentKn1ght/enterprise-platform/branch/main/graph/badge.svg)](https://codecov.io/gh/SilentKn1ght/enterprise-platform)

A production-ready Node.js REST API demonstrating modern DevOps practices: Infrastructure as Code, containerization, CI/CD automation, comprehensive monitoring, and security hardening.

**Status:** ✅ Deployed and running on AWS ECS Fargate with PostgreSQL RDS

---

## 🎯 What This Project Shows

- ✅ **Infrastructure as Code** - Terraform managing AWS resources
- ✅ **Containerization** - Docker images built automatically and pushed to ECR
- ✅ **CI/CD Pipeline** - GitHub Actions auto-deploys on every push
- ✅ **Auto-Scaling** - ECS Fargate scales based on CPU/memory metrics
- ✅ **Monitoring Stack** - Prometheus, Grafana, and Loki for observability
- ✅ **Security Hardening** - Encryption, SSL, secrets management, VPC isolation
- ✅ **Cost Optimization** - Single NAT Gateway, right-sized instances, budget alerts
- ✅ **Professional Documentation** - Architecture, deployment, operations, and troubleshooting guides

---

## 🏗️ Architecture Overview

```
Internet (Users)
    ↓ HTTP/HTTPS
┌─────────────────────────┐
│ AWS ALB (Load Balancer) │
│      Port 80/443        │
└────────────┬────────────┘
             ↓
      ┌──────────────┐
      │   ECS Fargate│
      │  (2-6 tasks) │
      │  Node.js API │
      │   Port 3000  │
      └────────┬─────┘
               ↓
    ┌──────────────────────┐
    │ RDS PostgreSQL       │
    │ (db.t3.micro, 20GB)  │
    │ Private VPC Subnet   │
    └──────────────────────┘
```

**Key Infrastructure:**
- **Compute:** ECS Fargate (serverless containers)
- **Database:** PostgreSQL 15.4 with encryption and backups
- **Load Balancing:** Application Load Balancer with health checks
- **Networking:** VPC with public/private subnets, NAT Gateway
- **Container Registry:** AWS ECR for Docker images
- **Monitoring:** CloudWatch, Prometheus, Grafana, Loki
- **Secrets:** AWS Secrets Manager for credentials

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Cloud** | AWS (ECS Fargate, RDS, ALB, VPC) |
| **IaC** | Terraform 1.0+ |
| **Compute** | Node.js 18 on Alpine Linux |
| **Framework** | Express.js |
| **Database** | PostgreSQL 15.4 |
| **Monitoring** | CloudWatch, Prometheus, Grafana, Loki |
| **CI/CD** | GitHub Actions |
| **Containers** | Docker, ECR |
| **Secrets** | AWS Secrets Manager |

---

## 📚 Documentation

**Start here based on what you need:**

### For Understanding the System
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Complete system design, components, and how they work together
  - Network topology and VPC layout
  - ECS Fargate configuration and auto-scaling
  - RDS database setup and backup strategy
  - Security architecture and defense layers

### For Deploying & Monitoring (Currently Deployed ✅)
See the [ARCHITECTURE.md](docs/ARCHITECTURE.md) for system design details. Setup guides are available locally in `/docs` but not tracked in git (one-time deployment documentation).

- **CLOUDWATCH-GRAFANA-DEPLOYMENT.md** - Local reference guide for AWS monitoring setup
- **AWS-ENV-AND-MONITORING-SETUP.md** - Local reference for environment configuration  
- **GRAFANA-CLOUDWATCH-SETUP.md** - Local reference for Grafana integration

### For Troubleshooting
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Quick solutions for common problems
  - Deployment issues
  - Runtime errors and 5xx responses
  - Database connectivity and performance
  - Networking issues
  - Performance problems

### For Testing & Security
- **[Load-Testing-Guide.md](docs/Load-Testing-Guide.md)** - K6-based performance testing procedures
- **[security-audit-checklist.md](docs/security-audit-checklist.md)** - Security compliance verification

---

## 🚀 Quick Start

### Prerequisites
- AWS Account (free tier okay)
- AWS CLI configured
- Terraform 1.0+
- Docker 20.10+
- Git

### Deploy in 6 Steps

```bash
# 1. Clone repository
git clone https://github.com/SilentKn1ght/enterprise-platform.git
cd enterprise-platform

# 2. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration

# 3. Deploy infrastructure
terraform init
terraform plan
terraform apply

# 4. Verify deployment
ALB=$(terraform output -raw alb_dns_name)
curl http://$ALB/health
```

**Full details:** See [CLOUDWATCH-GRAFANA-DEPLOYMENT.md](docs/CLOUDWATCH-GRAFANA-DEPLOYMENT.md)

---

## 📊 Current Status

### Infrastructure
- ✅ VPC with public/private subnets
- ✅ ECS Fargate cluster and service
- ✅ Application Load Balancer
- ✅ RDS PostgreSQL with encryption
- ✅ Security groups and network ACLs
- ✅ IAM roles with least privilege
- ✅ CloudWatch monitoring and alarms

### Application
- ✅ Node.js REST API
- ✅ Health check endpoint
- ✅ API status endpoints
- ✅ Metrics export (Prometheus format)
- ✅ Structured logging
- ✅ Error handling

### CI/CD & DevOps
- ✅ GitHub Actions pipeline
- ✅ Automated Docker builds
- ✅ Push to ECR on every commit
- ✅ Auto-deploy to ECS
- ✅ Terraform state management
- ✅ Cost monitoring and budgets

### Security
- ✅ RDS encryption at rest
- ✅ SSL/TLS for database connections
- ✅ VPC isolation (private databases)
- ✅ Security group least privilege
- ✅ Secrets Manager integration
- ✅ ECR image scanning
- ✅ Security audit checklist

### Monitoring & Observability
- ✅ CloudWatch Logs
- ✅ CloudWatch Metrics
- ✅ CloudWatch Alarms
- ✅ Prometheus metrics
- ✅ Grafana dashboards
- ✅ Loki log aggregation
- ✅ Application performance monitoring

---

## 💰 Estimated Costs

**Monthly (Development Environment):**
- ECS Fargate: €24
- Application Load Balancer: €16
- RDS Database: €28
- NAT Gateway: €32
- CloudWatch/Monitoring: €12
- Other services: €8
- **Total: ~€120/month**

🎯 **Cost Optimization:**
- Use `./scripts/resource-control.sh` to stop/start services
- Stop dev environment 6pm-9am (saves €10-15/month)
- Scale down to min tasks during off-hours
- Delete NAT Gateway for aggressive savings (recreate when needed)

---

## 📁 Project Structure

```
enterprise-platform/
├── docs/
│   ├── ARCHITECTURE.md                      # System design & overview
│   ├── TROUBLESHOOTING.md                   # Problem solving guide
│   ├── Load-Testing-Guide.md                # Performance testing with K6
│   └── security-audit-checklist.md          # Security verification checklist
│   
│   ⚠️ One-time setup guides (not in git, local reference only):
│   ├── CLOUDWATCH-GRAFANA-DEPLOYMENT.md     # Monitoring setup reference
│   ├── AWS-ENV-AND-MONITORING-SETUP.md      # Environment setup reference
│   └── GRAFANA-CLOUDWATCH-SETUP.md          # Grafana integration reference
├── terraform/                       # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── modules/
│       ├── networking/
│       ├── ecs/
│       ├── rds/
│       └── alb/
├── services/
│   ├── api/                         # Node.js Express API
│   │   ├── app.js
│   │   ├── server.js
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── __tests__/
│   └── frontend/                    # HTML dashboard (optional)
├── monitoring/
│   ├── grafana/
│   ├── prometheus/
│   └── loki/
├── scripts/
│   ├── load-test.sh
│   ├── resource-control.sh
│   └── aws-cost-audit.sh
├── .github/workflows/
│   └── test.yml                     # GitHub Actions CI/CD
└── README.md (this file)
```

---

## 🔍 Key Endpoints

| Endpoint | Purpose | Example |
|----------|---------|---------|
| `GET /health` | Health check | `curl http://alb-dns/health` |
| `GET /metrics` | Prometheus metrics | `curl http://alb-dns/metrics` |
| `GET /api` | API root | `curl http://alb-dns/api` |
| `GET /api/status` | Service status | `curl http://alb-dns/api/status` |

---

## 🛡️ Security Features

- **Network Security:**
  - VPC isolation with public/private subnets
  - Security groups with least privilege
  - NAT Gateway for controlled outbound access
  - No direct internet access to database

- **Data Security:**
  - RDS encryption at rest (AES-256)
  - TLS/SSL for database connections
  - Secrets Manager for credentials
  - No hardcoded secrets in code

- **Application Security:**
  - ECR image scanning for vulnerabilities
  - Non-root container execution
  - Input validation and sanitization
  - Error handling without data leakage

- **Access Control:**
  - IAM roles (no access keys)
  - Least privilege policies
  - Resource-based policies
  - Audit logging (CloudTrail)

---

## 📈 Performance

**Baseline (from load testing):**
- Throughput: ~100 req/sec (2 tasks)
- Latency p50: 15ms
- Latency p95: 45ms
- Latency p99: 120ms
- Error rate: < 0.1%

**Scaling:**
- Scales from 2 to 6 tasks automatically
- Handles 300+ req/sec at max capacity
- Auto-scales up on high CPU/memory
- Cool-down periods prevent flapping

See [Load-Testing-Guide.md](docs/Load-Testing-Guide.md) for detailed procedures.

---

## 🚨 Monitoring & Alerts

Real-time alerts for:
- Application down (task failures)
- High CPU usage (>80%)
- High memory usage (>80%)
- Database connection pool exhaustion
- ALB target unhealthy
- High error rate (>5%)
- Slow response times (>1s)

All alerts send to CloudWatch. See [OPERATIONS.md](docs/OPERATIONS.md) for runbooks.

---

## 🔄 CI/CD Pipeline

Every push to `main` triggers:

1. ✅ Run tests (Jest)
2. ✅ Run linting (ESLint)
3. ✅ Build Docker image
4. ✅ Push to ECR
5. ✅ Update ECS service
6. ✅ Rolling deployment to production
7. ✅ Health checks pass/fail

Deployment time: ~3-5 minutes from push to live.

---

## 📖 Learning Resources

This project demonstrates:

- **DevOps Practices:**
  - Infrastructure as Code (Terraform)
  - CI/CD automation (GitHub Actions)
  - Container orchestration (ECS Fargate)
  - Auto-scaling and monitoring

- **Cloud Architecture:**
  - VPC design and networking
  - Load balancing and deployment
  - Database design and backup
  - Security and compliance

- **Professional Skills:**
  - Technical documentation
  - Operational procedures
  - Troubleshooting and debugging
  - Cost optimization

Perfect for building AWS and DevOps portfolio skills.

---

## 🤝 Contributing

Issues and pull requests welcome! Areas for improvement:

- Multi-region deployment
- HTTPS/TLS with ACM certificates
- Route 53 DNS management
- ElastiCache for caching layer
- AWS WAF integration
- X-Ray distributed tracing
- Kubernetes alternative (EKS)

---

## 📝 License

MIT License - See LICENSE file

---

## 🔗 Links

- [GitHub Repository](https://github.com/SilentKn1ght/enterprise-platform)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [Node.js Best Practices](https://nodejs.org/en/docs/)

---

## ❓ FAQ

**Q: Is this for learning or production?**  
A: Both. It follows production best practices but is optimized for cost in development. See DEPLOYMENT.md for production configuration changes.

**Q: How much does it cost?**  
A: ~€120/month for development environment. Costs scale with traffic. See cost-analysis.md for details.

**Q: Can I deploy to a different region?**  
A: Yes. Change `aws_region` in terraform.tfvars. Pricing varies by region.

**Q: How do I add more endpoints?**  
A: Edit services/api/app.js, push to main, and GitHub Actions auto-deploys.

**Q: Can I scale this to production?**  
A: Yes. See DEPLOYMENT.md for production configuration recommendations.

---

## 🆘 Need Help?

1. **Deployment issues?** → See [DEPLOYMENT.md](docs/DEPLOYMENT.md)
2. **System broken?** → See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
3. **Need to operate it?** → See [OPERATIONS.md](docs/OPERATIONS.md)
4. **Want to understand it?** → See [ARCHITECTURE.md](docs/ARCHITECTURE.md)
5. **Something else?** → Check AWS console or AWS support

---

**Last Updated:** March 8, 2026  
**Version:** 1.0.0  
**Maintainer:** [SilentKn1ght](https://github.com/SilentKn1ght)