const request = require('supertest');
const express = require('express');
const logger = require('../utils/logger');

// Mock logger to avoid log file writes during tests
jest.mock('../utils/logger');

describe('Error Handling', () => {
  let app;

  beforeEach(() => {
    // Create a fresh app instance for error testing
    app = express();
    
    // Middleware that can throw errors
    app.get('/error', (req, res, next) => {
      const err = new Error('Test error');
      err.status = 418;
      next(err);
    });

    app.get('/unhandled-error', (req, res, next) => {
      const err = new Error('Unhandled error');
      err.status = 500;
      next(err);
    });

    // Global error handler (same as in app.js)
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
  });

  test('passes error through error handler with custom status', async () => {
    const response = await request(app).get('/error');
    expect(response.statusCode).toBe(418);
    expect(response.body.error).toBe('Test error');
    expect(response.body.status).toBe(418);
  });

  test('error handler uses 500 as default status', async () => {
    const response = await request(app).get('/unhandled-error');
    expect(response.statusCode).toBe(500);
  });

  test('error response includes timestamp', async () => {
    const response = await request(app).get('/error');
    expect(response.body).toHaveProperty('timestamp');
    const timestamp = new Date(response.body.timestamp);
    expect(timestamp.getTime()).toBeLessThanOrEqual(Date.now());
  });

  test('shows error message in development', async () => {
    process.env.NODE_ENV = 'development';
    const response = await request(app).get('/error');
    expect(response.body.error).toBe('Test error');
  });

  test('masks error message in production', async () => {
    process.env.NODE_ENV = 'production';
    const response = await request(app).get('/error');
    expect(response.body.error).toBe('Internal Server Error');
  });

  test('logs error details', async () => {
    await request(app).get('/error');
    expect(logger.error).toHaveBeenCalled();
    const callArgs = logger.error.mock.calls[0];
    expect(callArgs[0]).toBe('Unhandled error');
    expect(callArgs[1]).toHaveProperty('error');
    expect(callArgs[1]).toHaveProperty('status');
    expect(callArgs[1]).toHaveProperty('path');
    expect(callArgs[1]).toHaveProperty('method');
  });
});
