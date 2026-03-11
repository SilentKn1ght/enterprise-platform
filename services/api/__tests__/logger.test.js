const logger = require('../utils/logger');
const fs = require('fs');

jest.mock('fs');

describe('Logger Utility', () => {
  let originalEnv;

  beforeEach(() => {
    originalEnv = process.env.NODE_ENV;
    jest.clearAllMocks();
    jest.spyOn(console, 'log').mockImplementation();
  });

  afterEach(() => {
    process.env.NODE_ENV = originalEnv;
    jest.restoreAllMocks();
  });

  describe('formatLog', () => {
    test('formats log with all required fields', () => {
      const result = logger.formatLog('INFO', 'Test message', { userId: 123 });
      const parsed = JSON.parse(result);
      
      expect(parsed.timestamp).toBeDefined();
      expect(parsed.level).toBe('INFO');
      expect(parsed.message).toBe('Test message');
      expect(parsed.userId).toBe(123);
      expect(parsed.pid).toBeDefined();
      expect(parsed.env).toBeDefined();
    });

    test('handles empty data object', () => {
      const result = logger.formatLog('WARN', 'No data');
      const parsed = JSON.parse(result);
      
      expect(parsed.message).toBe('No data');
      expect(parsed.level).toBe('WARN');
    });

    test('uses development env when NODE_ENV is not set', () => {
      delete process.env.NODE_ENV;
      const result = logger.formatLog('INFO', 'Env fallback');
      const parsed = JSON.parse(result);

      expect(parsed.env).toBe('development');
    });
  });

  describe('log', () => {
    test('logs to console', () => {
      logger.log('DEBUG', 'Console test', {});
      expect(console.log).toHaveBeenCalled();
    });

    test('writes to file in production', () => {
      process.env.NODE_ENV = 'production';
      fs.existsSync.mockReturnValue(true);
      fs.appendFileSync.mockImplementation();

      logger.log('ERROR', 'Production error', { code: 500 });

      expect(fs.appendFileSync).toHaveBeenCalled();
    });

    test('does not write to file in development', () => {
      process.env.NODE_ENV = 'development';
      fs.appendFileSync.mockImplementation();

      logger.log('INFO', 'Dev message', {});

      expect(fs.appendFileSync).not.toHaveBeenCalled();
    });

    test('uses default data object when data is omitted', () => {
      logger.log('INFO', 'No data argument');
      const payload = JSON.parse(console.log.mock.calls[0][0]);
      expect(payload.level).toBe('INFO');
      expect(payload.message).toBe('No data argument');
    });
  });

  describe('convenience methods', () => {
    test('info() logs at INFO level', () => {
      logger.info('Info message', { data: 'test' });
      const payload = JSON.parse(console.log.mock.calls[0][0]);
      expect(payload.level).toBe('INFO');
      expect(payload.message).toBe('Info message');
    });

    test('error() logs at ERROR level', () => {
      logger.error('Error message', { err: 'Something broke' });
      const payload = JSON.parse(console.log.mock.calls[0][0]);
      expect(payload.level).toBe('ERROR');
      expect(payload.message).toBe('Error message');
    });

    test('warn() logs at WARN level', () => {
      logger.warn('Warning message', { code: 429 });
      const payload = JSON.parse(console.log.mock.calls[0][0]);
      expect(payload.level).toBe('WARN');
      expect(payload.message).toBe('Warning message');
    });

    test('debug() logs only in non-production', () => {
      jest.spyOn(logger, 'log').mockImplementation();
      
      process.env.NODE_ENV = 'development';
      logger.debug('Debug message', {});
      expect(logger.log).toHaveBeenCalledWith('DEBUG', 'Debug message', {});

      logger.log.mockClear();
      
      process.env.NODE_ENV = 'production';
      logger.debug('Debug message', {});
      expect(logger.log).not.toHaveBeenCalled();
    });

    test('convenience methods support omitted data argument', () => {
      jest.spyOn(logger, 'log').mockImplementation();

      logger.info('Info without data');
      logger.error('Error without data');
      logger.warn('Warn without data');
      logger.debug('Debug without data');

      expect(logger.log).toHaveBeenCalledWith('INFO', 'Info without data', {});
      expect(logger.log).toHaveBeenCalledWith('ERROR', 'Error without data', {});
      expect(logger.log).toHaveBeenCalledWith('WARN', 'Warn without data', {});
      expect(logger.log).toHaveBeenCalledWith('DEBUG', 'Debug without data', {});
    });
  });

  describe('ensureLogDir', () => {
    test('creates log directory if it does not exist', () => {
      fs.existsSync.mockReturnValue(false);
      fs.mkdirSync.mockImplementation();

      logger.ensureLogDir();

      expect(fs.mkdirSync).toHaveBeenCalled();
    });

    test('does not create log directory if it already exists', () => {
      fs.existsSync.mockReturnValue(true);
      fs.mkdirSync.mockImplementation();

      logger.ensureLogDir();

      expect(fs.mkdirSync).not.toHaveBeenCalled();
    });
  });
});
