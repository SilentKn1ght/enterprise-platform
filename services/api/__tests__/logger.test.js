const logger = require('../utils/logger');
const fs = require('fs');
const path = require('path');

jest.mock('fs');
jest.mock('path');

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
  });

  describe('convenience methods', () => {
    test('info() logs at INFO level', () => {
      jest.spyOn(logger, 'log').mockImplementation();
      logger.info('Info message', { data: 'test' });
      expect(logger.log).toHaveBeenCalledWith('INFO', 'Info message', { data: 'test' });
    });

    test('error() logs at ERROR level', () => {
      jest.spyOn(logger, 'log').mockImplementation();
      logger.error('Error message', { err: 'Something broke' });
      expect(logger.log).toHaveBeenCalledWith('ERROR', 'Error message', { err: 'Something broke' });
    });

    test('warn() logs at WARN level', () => {
      jest.spyOn(logger, 'log').mockImplementation();
      logger.warn('Warning message', { code: 429 });
      expect(logger.log).toHaveBeenCalledWith('WARN', 'Warning message', { code: 429 });
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
