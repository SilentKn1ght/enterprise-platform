const { authenticateToken } = require('../utils/auth');

describe('Authentication Middleware', () => {
  let req, res, next, originalEnv;

  beforeEach(() => {
    originalEnv = process.env.API_KEY;
    req = {
      headers: {},
      ip: '127.0.0.1',
      path: '/api/status'
    };
    res = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn()
    };
    next = jest.fn();
  });

  afterEach(() => {
    process.env.API_KEY = originalEnv;
  });

  test('allows request when API_KEY is not configured (dev mode)', () => {
    delete process.env.API_KEY;
    authenticateToken(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  test('returns 401 when authorization header is missing', () => {
    process.env.API_KEY = 'test-key';
    authenticateToken(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: 'Unauthorized',
        message: expect.stringContaining('Missing or invalid')
      })
    );
    expect(next).not.toHaveBeenCalled();
  });

  test('returns 403 when token is invalid', () => {
    process.env.API_KEY = 'correct-key';
    req.headers.authorization = 'Bearer wrong-key';
    authenticateToken(req, res, next);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: 'Forbidden',
        message: 'Invalid API key'
      })
    );
    expect(next).not.toHaveBeenCalled();
  });

  test('calls next() when token is valid', () => {
    const validToken = 'correct-key';
    process.env.API_KEY = validToken;
    req.headers.authorization = `Bearer ${validToken}`;
    authenticateToken(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  test('extracts Bearer token correctly from authorization header', () => {
    const validToken = 'my-test-token-12345';
    process.env.API_KEY = validToken;
    req.headers.authorization = `Bearer ${validToken}`;
    authenticateToken(req, res, next);
    expect(next).toHaveBeenCalled();
  });
});
