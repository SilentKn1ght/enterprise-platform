const request = require('supertest');
const app = require('../app');

describe('Integration Tests', () => {
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

  test('serves index.html for unknown non-API routes (SPA)', async () => {
    const response = await request(app).get('/unknown');
    expect(response.statusCode).toBe(200);
    expect(response.type).toBe('text/html');
  });
});