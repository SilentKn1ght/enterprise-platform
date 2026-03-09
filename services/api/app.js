const express = require('express');
const promClient = require('prom-client');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const logger = require('./utils/logger');
const { authenticateToken } = require('./utils/auth');
const os = require('os');

const app = express();

// CORS middleware - restrict to specified origins
const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost:3001,http://localhost:3000').split(',');
app.use((req, res, next) => {
  const origin = req.headers.origin;
  // Only set CORS headers if origin is in allowed list
  if (origin && allowedOrigins.includes(origin)) {
    res.header('Access-Control-Allow-Origin', origin);
    res.header('Access-Control-Allow-Credentials', 'true');
  }
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  
  next();
});

// Security middleware
app.use(helmet());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api/', limiter);

// Body parsing middleware
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ limit: '10kb', extended: true }));

// Health check should not be rate limited
const healthLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
});
app.use('/health', healthLimiter);

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

// Middleware - Track request metrics and handle connection lifecycle
app.use((req, res, next) => {
  const start = Date.now();
  activeConnections.inc();

  // Track completion
  const recordMetrics = () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
    httpRequestsTotal.labels(req.method, req.route?.path || req.path, res.statusCode).inc();
    activeConnections.dec();
    
    // Remove listeners to prevent memory leaks
    res.removeListener('finish', recordMetrics);
    res.removeListener('close', recordMetrics);
  };

  // Handle both normal completion and socket close
  res.on('finish', recordMetrics);
  res.on('close', recordMetrics);

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

// Protect metrics endpoint with API key if configured
app.get('/metrics', authenticateToken, async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    logger.error('Metrics generation failed', { error: error.message });
    res.status(500).json({ error: 'Failed to generate metrics' });
  }
});

app.get('/api', (req, res) => {
  res.json({ 
    message: 'Enterprise Platform API',
    version: '1.0.0',
    endpoints: ['/health', '/metrics', '/api/status', '/api/data']
  });
});

// Protect status endpoint with API key if configured
app.get('/api/status', authenticateToken, (req, res) => {
  res.json({
    status: 'running',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    hostname: os.hostname(),
    platform: process.platform,
    nodeVersion: process.version
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

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path,
    method: req.method
  });
});

// Global error handler
app.use((err, req, res, _next) => {
  const status = err.status || 500;
  const message = process.env.NODE_ENV === 'production' ? 'Internal Server Error' : err.message;
  
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    status,
    path: req.path,
    method: req.method
  });
  
  res.status(status).json({
    error: message,
    status,
    timestamp: new Date().toISOString()
  });
});

module.exports = app;