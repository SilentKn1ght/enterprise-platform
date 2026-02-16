const request = require('supertest');
const app = require('../app');

describe('Metrics Endpoint', () => {
  test('GET /metrics returns 200', async () => {
    const response = await request(app).get('/metrics');
    expect(response.statusCode).toBe(200);
  });

  test('GET /metrics returns prometheus format', async () => {
    const response = await request(app).get('/metrics');
    expect(response.text).toContain('# HELP');
    expect(response.text).toContain('# TYPE');
  });

  test('GET /metrics includes http_requests_total', async () => {
    const response = await request(app).get('/metrics');
    expect(response.text).toContain('http_requests_total');
  });

  test('GET /metrics includes process metrics', async () => {
    const response = await request(app).get('/metrics');
    expect(response.text).toContain('process_cpu_seconds_total');
    expect(response.text).toContain('process_resident_memory_bytes');
  });
});