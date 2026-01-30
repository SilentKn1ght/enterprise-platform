const express = require('express');
const prometheus = require('prom-client');
const os = require('os');

// Initialize metrics
const httpRequestDuration = new prometheus.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.5, 1, 2, 5]
});

const httpRequestTotal = new prometheus.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const appVersion = new prometheus.Gauge({
  name: 'app_info',
  help: 'Application info',
  labelNames: ['version', 'environment'],
  registers: [prometheus.register]
});

appVersion.set(
  { version: '1.0.0', environment: 'development' },
  1
);

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware to track metrics
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration
      .labels(req.method, req.path, res.statusCode)
      .observe(duration);
    
    httpRequestTotal
      .labels(req.method, req.path, res.statusCode)
      .inc();
  });
  
  next();
});

// Routes

// Health check endpoint (used by load balancers)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(await prometheus.register.metrics());
});

// API endpoint
app.get('/api', (req, res) => {
  res.json({
    message: 'Enterprise Platform API',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Status endpoint
app.get('/api/status', (req, res) => {
  res.json({
    status: 'running',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    hostname: os.hostname(),
    platform: os.platform()
  });
});

// Simple data endpoint
app.get('/api/data', (req, res) => {
  res.json({
    data: [
      { id: 1, name: 'Item 1', created: new Date() },
      { id: 2, name: 'Item 2', created: new Date() },
      { id: 3, name: 'Item 3', created: new Date() }
    ]
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path,
    method: req.method
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`✅ Server running on http://localhost:${PORT}`);
  console.log(`📊 Metrics available at http://localhost:${PORT}/metrics`);
  console.log(`❤️  Health check at http://localhost:${PORT}/health`);
});
