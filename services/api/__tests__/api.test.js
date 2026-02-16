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
});