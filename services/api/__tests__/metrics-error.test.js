const request = require('supertest');
const express = require('express');

// Create a test app with mocked metrics
describe('Metrics Endpoint Coverage', () => {
  let app;
  let mockRegister;

  beforeEach(() => {
    app = express();
    
    // Mock the prom-client registry
    mockRegister = {
      contentType: 'text/plain; version=0.0.4; charset=utf-8',
      metrics: jest.fn().mockResolvedValue('# HELP test Test metric\n# TYPE test gauge\ntest 1\n')
    };

    // Authentication middleware (simulated)
    const authenticateToken = (req, res, next) => {
      if (!process.env.API_KEY) {
        return next();
      }
      const token = req.headers['authorization']?.split(' ')[1];
      if (!token || token !== process.env.API_KEY) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      next();
    };

    // Metrics endpoint with error handling
    app.get('/metrics', authenticateToken, async (req, res) => {
      try {
        res.set('Content-Type', mockRegister.contentType);
        res.end(await mockRegister.metrics());
      } catch (error) {
        console.error('Metrics generation failed', { error: error.message });
        res.status(500).json({ error: 'Failed to generate metrics' });
      }
    });
  });

  test('metrics endpoint returns metrics data', async () => {
    delete process.env.API_KEY;
    const response = await request(app).get('/metrics');
    expect(response.statusCode).toBe(200);
    expect(response.text).toContain('test');
  });

  test('metrics endpoint handles errors gracefully', async () => {
    delete process.env.API_KEY;
    mockRegister.metrics.mockRejectedValueOnce(new Error('Registry error'));
    
    const response = await request(app).get('/metrics');
    expect(response.statusCode).toBe(500);
  });

  test('metrics endpoint requires authentication when API_KEY is set', async () => {
    process.env.API_KEY = 'secret-key';
    const response = await request(app).get('/metrics');
    expect(response.statusCode).toBe(401);
  });

  test('metrics endpoint works with valid authentication', async () => {
    process.env.API_KEY = 'secret-key';
    const response = await request(app)
      .get('/metrics')
      .set('Authorization', 'Bearer secret-key');
    expect(response.statusCode).toBe(200);
  });
});
