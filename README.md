# Enterprise DevOps Platform

[![Test & Lint](https://github.com/SilentKn1ght/enterprise-platform/actions/workflows/test.yml/badge.svg)](https://github.com/SilentKn1ght/enterprise-platform/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/SilentKn1ght/enterprise-platform/branch/main/graph/badge.svg)](https://codecov.io/gh/SilentKn1ght/enterprise-platform)

A production-ready platform demonstrating CI/CD, Infrastructure-as-Code, and production monitoring.

## 🎯 Project Goals

- [x] Build a 3-tier application (frontend, API, database)
- [x] Set up complete monitoring (Prometheus, Grafana, Loki)
- [x] Create CI/CD pipeline (GitHub Actions)
- [ ] Define infrastructure as code (Terraform)
- [ ] Deploy to AWS (free tier)
- [ ] Document everything professionally

## 🛠️ Technologies

- **Containerization:** Docker, Docker Compose
- **CI/CD:** GitHub Actions
- **Infrastructure:** Terraform, AWS (ECS, RDS, ALB)
- **Monitoring:** Prometheus, Grafana, Loki
- **Backend:** Node.js, PostgreSQL, Redis
- **Frontend:** React (simple dashboard)

## 📁 Project Structure

```
enterprise-platform/
├── .github/workflows/      # GitHub Actions
├── terraform/              # Infrastructure code
├── services/               # Application code
│   ├── frontend/
│   ├── api/
│   ├── database/
│   └── cache/
├── monitoring/             # Observability stack
├── automation/             # Auto-remediation scripts
├── scripts/                # Deployment scripts
└── docs/                   # Documentation

```

## 🚀 Quick Start (Local Development)

1. Clone the repository
2. Install Docker
3. Run: `docker-compose up`
4. Visit: http://localhost:3000

## 📚 Documentation

- [Monitoring Guide](docs/MONITORING.md)
- [Runbooks](docs/RUNBOOKS.md)