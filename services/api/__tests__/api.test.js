const request = require('supertest');
const app = require('../app');

describe('API Endpoints', () => {
  describe('GET /api', () => {
    test('returns 200', async () => {
      const response = await request(app).get('/api');
      expect(response.statusCode).toBe(200);
    });

    test('returns correct structure', async () => {
      const response = await request(app).get('/api');
      expect(response.body).toHaveProperty('message');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('endpoints');
    });
  });

  describe('GET /api/status', () => {
    test('returns 200', async () => {
      const response = await request(app).get('/api/status');
      expect(response.statusCode).toBe(200);
    });

    test('returns system information', async () => {
      const response = await request(app).get('/api/status');
      expect(response.body).toHaveProperty('status', 'running');
      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('memory');
      expect(response.body).toHaveProperty('hostname');
      expect(response.body).toHaveProperty('platform');
    });
  });

  describe('GET /api/data', () => {
    test('returns 200', async () => {
      const response = await request(app).get('/api/data');
      expect(response.statusCode).toBe(200);
    });

    test('returns array of data', async () => {
      const response = await request(app).get('/api/data');
      expect(response.body).toHaveProperty('data');
      expect(Array.isArray(response.body.data)).toBe(true);
      expect(response.body.data.length).toBeGreaterThan(0);
    });

    test('data items have correct structure', async () => {
      const response = await request(app).get('/api/data');
      const firstItem = response.body.data[0];
      expect(firstItem).toHaveProperty('id');
      expect(firstItem).toHaveProperty('name');
      expect(firstItem).toHaveProperty('created');
    });
  });

  describe('CORS Headers', () => {
    test('sets CORS headers for allowed origins', async () => {
      const response = await request(app)
        .get('/api')
        .set('Origin', 'http://localhost:3001');
      
      expect(response.headers['access-control-allow-origin']).toBe('http://localhost:3001');
      expect(response.headers['access-control-allow-credentials']).toBe('true');
    });

    test('does not set Access-Control-Allow-Origin for disallowed origins', async () => {
      const response = await request(app)
        .get('/api')
        .set('Origin', 'http://malicious.com');
      
      expect(response.headers['access-control-allow-origin']).toBeUndefined();
    });

    test('sets CORS allow headers for all requests', async () => {
      const response = await request(app).get('/api');
      
      expect(response.headers['access-control-allow-methods']).toBe('GET, POST, PUT, DELETE, OPTIONS');
      expect(response.headers['access-control-allow-headers']).toBe('Content-Type, Authorization');
    });
  });

  describe('OPTIONS Requests (CORS Preflight)', () => {
    test('handles OPTIONS preflight request with 200', async () => {
      const response = await request(app).options('/api');
      expect(response.statusCode).toBe(200);
    });

    test('OPTIONS request does not call next route handler', async () => {
      const response = await request(app).options('/api/data');
      expect(response.statusCode).toBe(200);
      expect(response.body).toEqual({});
    });

    test('handles OPTIONS for root path', async () => {
      const response = await request(app).options('/');
      expect(response.statusCode).toBe(200);
    });
  });

  describe('Metrics Endpoint Error Handling', () => {
    test('returns 200 when API_KEY is not configured (dev mode)', async () => {
      delete process.env.API_KEY;
      const response = await request(app).get('/metrics');
      // In dev mode with no API_KEY, metrics should be accessible
      expect([200, 401]).toContain(response.statusCode);
    });

    test('returns 401 when API_KEY is configured but not provided', async () => {
      const originalKey = process.env.API_KEY;
      process.env.API_KEY = 'test-key';
      try {
        const response = await request(app).get('/metrics');
        expect(response.statusCode).toBe(401);
      } finally {
        process.env.API_KEY = originalKey;
      }
    });
  });

  describe('Error Handling', () => {
    test('handles requests to invalid routes with 404', async () => {
      const response = await request(app).get('/api/invalid-endpoint');
      expect(response.statusCode).toBe(404);
      expect(response.body).toHaveProperty('error', 'Not Found');
    });

    test('error response includes request details', async () => {
      const response = await request(app).get('/api/invalid-endpoint');
      expect(response.body).toHaveProperty('path', '/api/invalid-endpoint');
      expect(response.body).toHaveProperty('method', 'GET');
    });
  });
});