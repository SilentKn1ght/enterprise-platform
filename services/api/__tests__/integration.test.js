const request = require('supertest');
const app = require('../app');

describe('Integration Tests', () => {
  test('root path is handled (serves frontend or returns not found)', async () => {
    const response = await request(app).get('/');
    expect([200, 404]).toContain(response.statusCode);
  });

  test('complete flow: health → api → status → data', async () => {
    // 1. Check health
    const health = await request(app).get('/health');
    expect(health.statusCode).toBe(200);

    // 2. Get API info
    const api = await request(app).get('/api');
    expect(api.statusCode).toBe(200);

    // 3. Get status
    const status = await request(app).get('/api/status');
    expect(status.statusCode).toBe(200);

    // 4. Get data
    const data = await request(app).get('/api/data');
    expect(data.statusCode).toBe(200);
    expect(data.body.data).toHaveLength(3);
  });

  test('metrics are incremented after requests', async () => {
    // Get initial metrics
    const metrics1 = await request(app).get('/metrics');
    const initialText = metrics1.text;

    // Make some requests
    await request(app).get('/health');
    await request(app).get('/api');
    await request(app).get('/api/status');

    // Get updated metrics
    const metrics2 = await request(app).get('/metrics');
    
    // Verify metrics contain request counts
    expect(metrics2.text).toContain('http_requests_total');
    expect(metrics2.text.length).toBeGreaterThan(initialText.length);
  });

  test('404 for unknown API routes', async () => {
    const response = await request(app).get('/api/unknown');
    expect(response.statusCode).toBe(404);
  });

  test('404 for unknown metrics-prefixed routes', async () => {
    const response = await request(app).get('/metrics/unknown');
    expect(response.statusCode).toBe(404);
    expect(response.body).toHaveProperty('error', 'Not Found');
  });

  test('unknown non-API routes are handled (SPA fallback or not found)', async () => {
    const response = await request(app).get('/unknown');
    expect([200, 404]).toContain(response.statusCode);
  });

  test('masks malformed URI errors in production', async () => {
    const originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';

    try {
      const response = await request(app).get('/%');
      expect([400, 500]).toContain(response.statusCode);
      expect(response.body).toHaveProperty('error', 'Internal Server Error');
    } finally {
      process.env.NODE_ENV = originalEnv;
    }
  });

  test('defaults to 500 when error has no status', async () => {
    const routeLayer = app._router.stack.find((layer) => layer.route && layer.route.path === '/');
    const originalHandler = routeLayer.route.stack[0].handle;

    routeLayer.route.stack[0].handle = (_req, _res, next) => {
      next(new Error('Synthetic error without status'));
    };

    try {
      const response = await request(app).get('/');
      expect(response.statusCode).toBe(500);
      expect(response.body).toHaveProperty('status', 500);
    } finally {
      routeLayer.route.stack[0].handle = originalHandler;
    }
  });
});