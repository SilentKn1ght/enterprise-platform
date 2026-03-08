# Runbooks (Deprecated - See OPERATIONS.md)

⚠️ **This file is deprecated.** It covers Docker Compose-based operations, which is no longer the primary deployment method.

**For AWS ECS Fargate operations, see:** [OPERATIONS.md](OPERATIONS.md)

---

## Docker Compose Runbooks (Legacy)

These procedures are for local development only, using Docker Compose. For production AWS operations, refer to OPERATIONS.md.

### ApplicationDown Alert

**What it means:** The application is not responding to health checks.

**Investigation:**
```bash
# 1. Check if container is running
docker-compose ps api

# 2. Check logs
docker-compose logs api --tail=50

# 3. Check resource usage
docker stats api
```

**Resolution:**
```bash
# Restart the application
docker-compose restart api

# If restart fails, rebuild
docker-compose up --build -d api
```

---

### HighErrorRate Alert

**What it means:** More than 5% of requests are returning 5xx errors.

**Investigation:**
```bash
# 1. Check recent error logs
docker-compose logs api | grep -i error

# 2. Query specific error in Prometheus
# Go to: http://localhost:9090
# Query: rate(http_requests_total{status_code=~"5.."}[5m])

# 3. Check which endpoints are failing
# In Grafana: HTTP Performance dashboard → Status Codes panel
```

---

### HighResponseTime Alert

**What it means:** 95th percentile response time exceeds 2 seconds.

**Investigation:**
```bash
# 1. Check CPU and memory
# In Grafana: System Metrics dashboard

# 2. Identify slow endpoints
# In Grafana: HTTP Performance → Slowest Endpoints

# 3. Check for database slow queries
docker-compose logs db | grep "slow"
```

---

### HighMemoryUsage Alert

**What it means:** Application using more than 500MB of memory.

**Investigation:**
```bash
# 1. Check memory breakdown
docker stats api

# 2. Look for memory leaks in logs
docker-compose logs api | grep -i "heap\|memory"
```

---

### HighCPUUsage Alert

**What it means:** CPU usage exceeds 80%.

**Investigation:**
```bash
# 1. Check what's using CPU
docker stats

# 2. Check request rate and optimize code
# In Grafana: Application Overview → HTTP Request Rate
```

---

**⚠️ For all production operations on AWS, use [OPERATIONS.md](OPERATIONS.md)**
- Implement rate limiting
- Optimize algorithms