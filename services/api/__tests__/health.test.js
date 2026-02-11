const request = require('supertest');
const express = require('express');

// Import your app (we'll refactor index.js to export app)
const app = require('../app');

describe('Health Endpoint', () => {
  test('GET /health returns 200', async () => {
    const response = await request(app).get('/health');
    expect(response.statusCode).toBe(200);
  });

  test('GET /health returns correct structure', async () => {
    const response = await request(app).get('/health');
    expect(response.body).toHaveProperty('status');
    expect(response.body).toHaveProperty('timestamp');
    expect(response.body).toHaveProperty('uptime');
    expect(response.body.status).toBe('healthy');
  });

  test('GET /health returns valid timestamp', async () => {
    const response = await request(app).get('/health');
    const timestamp = new Date(response.body.timestamp);
    expect(timestamp instanceof Date).toBe(true);
    expect(isNaN(timestamp.getTime())).toBe(false);
  });
});