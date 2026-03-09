const fs = require('fs');
const path = require('path');

// Simple JSON logger (Winston alternative for minimal dependencies)
class Logger {
  constructor() {
    this.logDir = path.join(__dirname, '..', 'logs');
    this.ensureLogDir();
  }

  ensureLogDir() {
    if (!fs.existsSync(this.logDir)) {
      fs.mkdirSync(this.logDir, { recursive: true });
    }
  }

  formatLog(level, message, data = {}) {
    return JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      message,
      ...data,
      pid: process.pid,
      env: process.env.NODE_ENV || 'development'
    });
  }

  log(level, message, data = {}) {
    const logString = this.formatLog(level, message, data);
    console.log(logString);
    
    // Write to file only in production
    if (process.env.NODE_ENV === 'production') {
      const logFile = path.join(this.logDir, `${level}.log`);
      fs.appendFileSync(logFile, logString + '\n');
    }
  }

  info(message, data = {}) {
    this.log('INFO', message, data);
  }

  error(message, data = {}) {
    this.log('ERROR', message, data);
  }

  warn(message, data = {}) {
    this.log('WARN', message, data);
  }

  debug(message, data = {}) {
    if (process.env.NODE_ENV !== 'production') {
      this.log('DEBUG', message, data);
    }
  }
}

module.exports = new Logger();
