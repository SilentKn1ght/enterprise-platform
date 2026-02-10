# Monitoring Guide

## Overview

This project uses the Prometheus + Grafana + Loki stack for observability.

## Architecture

```
Application → Prometheus (metrics)
           → Promtail → Loki (logs)

Prometheus → Grafana (dashboards)
          → Alertmanager (alerts)
```

## Accessing Monitoring

- **Application**: http://localhost:3000
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001 (admin/admin123)
- **Alertmanager**: http://localhost:9093
- **Loki**: http://localhost:3100

## Dashboards

### 1. Application Overview
- HTTP request rate
- Response times
- Active connections
- Memory and CPU usage

### 2. System Metrics
- System-level resource usage
- File descriptors
- Network I/O

### 3. HTTP Performance
- Request rates by method
- Response time percentiles
- Status code distribution
- Slowest endpoints

### 4. Alerts Overview
- Active alerts
- Alert timeline
- Alerts by severity

### 5. Business Metrics
- Total requests
- Success rate
- Uptime percentage

## Metrics Exposed

| Metric | Type | Description |
|--------|------|-------------|
| `http_requests_total` | Counter | Total HTTP requests |
| `http_request_duration_seconds` | Histogram | Request duration |
| `active_connections` | Gauge | Current active connections |
| `process_cpu_seconds_total` | Counter | CPU time used |
| `process_resident_memory_bytes` | Gauge | Memory usage |

## Alert Rules

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| ApplicationDown | > 1 min | Critical | App not responding |
| HighErrorRate | > 5% | Warning | Too many 5xx errors |
| HighResponseTime | > 2s | Warning | Slow responses |
| HighMemoryUsage | > 500MB | Warning | Memory pressure |
| HighCPUUsage | > 80% | Warning | CPU saturation |

## Troubleshooting

### No metrics in Grafana
1. Check Prometheus targets: http://localhost:9090/targets
2. All should be UP
3. If DOWN, check app is running: `docker-compose ps`

### Alerts not firing
1. Check alert rules loaded: http://localhost:9090/alerts
2. Check Alertmanager config: http://localhost:9093/#/status
3. Check webhook receiver logs: `docker-compose logs webhook-receiver`

### Logs not appearing
1. Check Loki is running: `curl http://localhost:3100/ready`
2. Check Promtail is scraping: `docker-compose logs promtail`
3. Verify Loki data source in Grafana

## Best Practices

1. **Always monitor these 4 golden signals:**
   - Latency (response time)
   - Traffic (request rate)
   - Errors (error rate)
   - Saturation (resource usage)

2. **Set meaningful thresholds:**
   - Based on actual traffic patterns
   - Avoid alert fatigue

3. **Document every alert:**
   - What it means
   - How to investigate
   - How to fix