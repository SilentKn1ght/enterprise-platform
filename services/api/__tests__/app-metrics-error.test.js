const request = require('supertest');

const createMetricWithLabels = () => ({
  labels: () => ({
    observe: jest.fn(),
    inc: jest.fn(),
  }),
});

describe('App metrics error handling', () => {
  test('returns 500 when Prometheus registry throws', async () => {
    jest.resetModules();

    const loggerError = jest.fn();

    jest.doMock('prom-client', () => ({
      Registry: jest.fn().mockImplementation(() => ({
        contentType: 'text/plain; version=0.0.4; charset=utf-8',
        registerMetric: jest.fn(),
        metrics: jest.fn().mockRejectedValue(new Error('registry unavailable')),
      })),
      collectDefaultMetrics: jest.fn(),
      Histogram: jest.fn().mockImplementation(createMetricWithLabels),
      Counter: jest.fn().mockImplementation(createMetricWithLabels),
      Gauge: jest.fn().mockImplementation(() => ({
        inc: jest.fn(),
        dec: jest.fn(),
      })),
    }));

    jest.doMock('../utils/logger', () => ({
      error: loggerError,
      warn: jest.fn(),
      info: jest.fn(),
      debug: jest.fn(),
      log: jest.fn(),
    }));

    const app = require('../app');

    delete process.env.API_KEY;
    const response = await request(app).get('/metrics');

    expect(response.statusCode).toBe(500);
    expect(loggerError).toHaveBeenCalledWith('Metrics generation failed', { error: 'registry unavailable' });

    jest.dontMock('prom-client');
    jest.dontMock('../utils/logger');
  });
});
