const app = require('./app');
const logger = require('./utils/logger');
const { validateEnvironment } = require('./utils/env');

// Validate environment at startup
try {
  validateEnvironment();
} catch (error) {
  logger.error('Startup failed', { error: error.message });
  process.exit(1);
}

const PORT = process.env.PORT || 3000;

const server = app.listen(PORT, () => {
  logger.info('Server started', { port: PORT, metricsUrl: `http://localhost:${PORT}/metrics` });
});

// Graceful shutdown
const gracefulShutdown = (signal) => {
  logger.info('Shutdown signal received', { signal });
  
  server.close(() => {
    logger.info('Server closed successfully');
    process.exit(0);
  });
  
  // Force exit after 10 seconds
  setTimeout(() => {
    logger.error('Force shutdown after timeout', { timeoutSeconds: 10 });
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
