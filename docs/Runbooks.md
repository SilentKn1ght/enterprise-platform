# Runbooks

## ApplicationDown Alert

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

**Prevention:**
- Add health check retries
- Implement graceful shutdown
- Monitor resource limits

---

## HighErrorRate Alert

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

**Resolution:**
- Identify failing endpoint from logs
- Check database connectivity
- Check external dependencies
- Review recent code changes

**Prevention:**
- Add retry logic
- Implement circuit breakers
- Add better error handling

---

## HighResponseTime Alert

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

**Resolution:**
- Scale horizontally (add more instances)
- Optimize slow queries
- Add caching layer
- Review recent code changes

**Prevention:**
- Add query timeouts
- Implement caching
- Optimize database indexes

---

## HighMemoryUsage Alert

**What it means:** Application using more than 500MB of memory.

**Investigation:**
```bash
# 1. Check memory breakdown
docker stats api

# 2. Look for memory leaks in logs
docker-compose logs api | grep -i "heap\|memory"

# 3. Check for memory-intensive operations
# Review recent endpoint calls in Grafana
```

**Resolution:**
```bash
# Short term: Restart application
docker-compose restart api

# Long term: Profile and fix memory leak
# Use Node.js --inspect flag
```

**Prevention:**
- Implement memory limits
- Add heap snapshots
- Profile memory usage
- Implement proper cleanup

---

## HighCPUUsage Alert

**What it means:** CPU usage exceeds 80%.

**Investigation:**
```bash
# 1. Check what's using CPU
docker stats

# 2. Check request rate
# In Grafana: Application Overview → HTTP Request Rate

# 3. Look for infinite loops or heavy computation
docker-compose logs api
```

**Resolution:**
- Scale horizontally (add instances)
- Optimize CPU-intensive code
- Add rate limiting
- Implement caching

**Prevention:**
- Add CPU profiling
- Implement rate limiting
- Optimize algorithms