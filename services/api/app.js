const express = require('express');
const promClient = require('prom-client');

const app = express();

// Prometheus setup
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register, prefix: 'api_' });

// Custom metrics
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.5, 1, 2, 5]
});
register.registerMetric(httpRequestDuration);

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});
register.registerMetric(httpRequestsTotal);

const activeConnections = new promClient.Gauge({
  name: 'active_connections',
  help: 'Number of active connections'
});
register.registerMetric(activeConnections);

// Middleware
app.use((req, res, next) => {
  const start = Date.now();
  activeConnections.inc();

  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
    httpRequestsTotal.labels(req.method, req.route?.path || req.path, res.statusCode).inc();
    activeConnections.dec();
  });

  next();
});

// Routes
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/api', (req, res) => {
  res.json({ 
    message: 'Enterprise Platform API',
    version: '1.0.0',
    endpoints: ['/health', '/metrics', '/api/status', '/api/data']
  });
});

app.get('/api/status', (req, res) => {
  res.json({
    status: 'running',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    hostname: require('os').hostname(),
    platform: process.platform
  });
});

app.get('/api/data', (req, res) => {
  res.json({
    data: [
      { id: 1, name: 'Item 1', created: new Date().toISOString() },
      { id: 2, name: 'Item 2', created: new Date().toISOString() },
      { id: 3, name: 'Item 3', created: new Date().toISOString() }
    ]
  });
});

module.exports = app;