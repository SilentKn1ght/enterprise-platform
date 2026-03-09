const logger = require('./logger');

// Validate required environment variables at startup
function validateEnvironment() {
  const required = [
    'NODE_ENV'
  ];

  const missing = [];

  for (const env of required) {
    if (!process.env[env]) {
      missing.push(env);
    }
  }

  if (missing.length > 0) {
    logger.error('Missing required environment variables', { missing });
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }

  // Log configured environment
  const envConfig = {
    NODE_ENV: process.env.NODE_ENV,
    PORT: process.env.PORT || 3000,
    API_KEY_CONFIGURED: !!process.env.API_KEY
  };

  logger.info('Environment validated', envConfig);
  return true;
}

module.exports = { validateEnvironment };
