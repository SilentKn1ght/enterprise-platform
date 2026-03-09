// Simple request validation using regex patterns
// In production, use Joi, Zod, or similar for robust validation

const validators = {
  // Validate query parameter is a positive integer
  positiveInteger: (value) => {
    if (!value) return { valid: true, value: null };
    const num = parseInt(value, 10);
    if (isNaN(num) || num <= 0) {
      return { valid: false, error: 'Must be a positive integer' };
    }
    return { valid: true, value: num };
  },

  // Validate email format
  email: (value) => {
    if (!value) return { valid: true, value: null };
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(value)) {
      return { valid: false, error: 'Invalid email format' };
    }
    return { valid: true, value };
  },

  // Validate string length
  string: (value, options = {}) => {
    if (!value && options.required) {
      return { valid: false, error: 'Field is required' };
    }
    if (!value) return { valid: true, value: null };

    const { minLength = 0, maxLength = 1000 } = options;
    if (value.length < minLength || value.length > maxLength) {
      return {
        valid: false,
        error: `String length must be between ${minLength} and ${maxLength}`
      };
    }
    return { valid: true, value: value.trim() };
  }
};

// Middleware to validate query parameters
function validateQuery(schema) {
  return (req, res, next) => {
    const errors = {};

    for (const [key, validator] of Object.entries(schema)) {
      const value = req.query[key];
      const result = validator(value);

      if (!result.valid) {
        errors[key] = result.error;
      } else {
        req.query[key] = result.value;
      }
    }

    if (Object.keys(errors).length > 0) {
      return res.status(400).json({
        error: 'Validation failed',
        details: errors
      });
    }

    next();
  };
}

// Middleware to validate request body
function validateBody(schema) {
  return (req, res, next) => {
    const errors = {};

    for (const [key, validator] of Object.entries(schema)) {
      const value = req.body[key];
      const result = validator(value);

      if (!result.valid) {
        errors[key] = result.error;
      } else {
        req.body[key] = result.value;
      }
    }

    if (Object.keys(errors).length > 0) {
      return res.status(400).json({
        error: 'Validation failed',
        details: errors
      });
    }

    next();
  };
}

module.exports = {
  validators,
  validateQuery,
  validateBody
};
