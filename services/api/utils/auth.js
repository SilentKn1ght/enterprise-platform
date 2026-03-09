const logger = require('./logger');

// Simple Bearer token authentication
// In production, use JWT or OAuth2
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer token

  // Allow unauthenticated access if no API_KEY is configured (development mode)
  if (!process.env.API_KEY) {
    return next();
  }

  if (!token) {
    logger.warn('Unauthorized access attempt', {
      ip: req.ip,
      path: req.path
    });
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing or invalid authorization token'
    });
  }

  if (token !== process.env.API_KEY) {
    logger.warn('Invalid token attempt', {
      ip: req.ip,
      path: req.path,
      tokenLength: token.length
    });
    return res.status(403).json({
      error: 'Forbidden',
      message: 'Invalid API key'
    });
  }

  next();
}

module.exports = { authenticateToken };
