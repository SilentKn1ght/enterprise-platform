# Contributing Guide

**Version:** 1.0.0  
**Last Updated:** March 9, 2026

Thank you for your interest in contributing to Enterprise Platform! This document provides guidelines and instructions for contributing.

---

## 📋 Code of Conduct

Be respectful, inclusive, and professional in all interactions. We're building a welcoming community.

---

## Getting Started

### 1. Fork & Setup

```bash
# Fork on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/enterprise-platform.git
cd enterprise-platform

# Add upstream remote
git remote add upstream https://github.com/SilentKn1ght/enterprise-platform.git

# Install dependencies
npm install
```

### 2. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

Feature branch naming:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code refactoring
- `test/` - Test additions

### 3. Make Changes

```bash
# Edit files
nano services/api/app.js

# Run tests
npm test

# Lint code
npm run lint

# Type check
npm run type-check
```

### 4. Commit Changes

```bash
# Stage changes
git add .

# Commit with meaningful message
git commit -m "feat: add new endpoint for user profiles

- Added GET /api/users/:id endpoint
- Added input validation
- Added tests for new endpoint
- Updated API documentation"
```

**Commit message format:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `test:` - Test additions
- `refactor:` - Code refactoring
- `perf:` - Performance improvement
- `chore:` - Build/dependency updates

### 5. Push and Create Pull Request

```bash
# Push to your fork
git push origin feature/your-feature-name

# Go to GitHub and create a Pull Request
# PR template auto-fills with required sections
```

**PR Description should include:**
- What problem does this solve?
- How does it solve it?
- What tests did you add?
- Any breaking changes?

---

## Types of Contributions

### 🐛 Bug Fixes

1. Describe the bug clearly
2. Provide reproduction steps
3. Include expected vs actual behavior
4. Test your fix works

**Example:**
```bash
# Bug: Health check endpoint returns 500

# Steps to reproduce:
# 1. Deploy latest code
# 2. curl http://alb-dns/health
# 3. See 500 error instead of 200

# Root cause: Missing environment variable
# Fix: Add proper error handling and default value
```

### ✨ Features

1. Check if feature request exists in issues
2. Discuss your approach first (open an issue)
3. Implement with tests
4. Update documentation
5. Submit PR

**Example features:**
- New API endpoints
- Monitoring improvements
- Deployment optimizations
- Documentation enhancements

### 📚 Documentation

Documentation improvements are highly valuable!

**Areas needing help:**
- Clarifying existing docs
- Adding examples
- Fixing typos
- Improving organization
- Translating (future)

### 🧪 Tests

```bash
# Add tests for new functionality
nano services/api/__tests__/health.test.js

# Test structure:
describe('GET /health', () => {
  test('should return 200 OK', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
});

# Run tests
npm test
```

---

## Development Setup

### Local Development Environment

```bash
# Start application
npm run dev

# Application runs at http://localhost:3000

# In another terminal, run tests
npm test

# Run tests in watch mode
npm test -- --watch

# Run linting
npm run lint

# Fix lint errors
npm run lint -- --fix
```

### Environment Variables

```bash
# Copy example
cp .env.example .env

# Edit with your values
# Required:
# - DATABASE_URL=postgresql://user:pass@localhost:5432/enterprise_db
# - NODE_ENV=development

# Optional:
# - LOG_LEVEL=debug
# - PORT=3000
```

### Database Setup (if modifying schema)

```bash
# If using Prisma ORM:
npm run db:migrate
npm run db:seed
```

---

## Code Standards

### TypeScript

- Use strict mode
- Type all function parameters
- Use interfaces over types (when possible)

```typescript
interface User {
  id: string;
  email: string;
  createdAt: Date;
}

async function getUser(id: string): Promise<User> {
  // implementation
}
```

### Testing

- Test coverage target: > 80%
- Write tests for new functionality
- Test both happy path and error cases

```typescript
describe('getUserById', () => {
  it('should return user when found', async () => {
    // Happy path test
  });

  it('should throw NotFound when user does not exist', async () => {
    // Error case test
  });

  it('should throw Unauthorized for invalid token', async () => {
    // Security test
  });
});
```

### Logging

- Use structured logging (JSON format)
- Log at appropriate levels: error, warn, info, debug

```typescript
logger.info({
  endpoint: '/api/users',
  method: 'GET',
  statusCode: 200,
  duration: 45
});

logger.error({
  endpoint: '/api/users',
  error: 'Database connection failed',
  timestamp: new Date()
});
```

### Error Handling

```typescript
// ❌ Bad
if (!user) {
  throw new Error('User not found');
}

// ✅ Good
if (!user) {
  throw new NotFoundError('User not found', {
    userId: id,
    endpoint: '/api/users/:id'
  });
}
```

---

## Terraform Changes

### Infrastructure Changes

If modifying Terraform:

```bash
cd terraform

# Format code
terraform fmt -recursive

# Validate
terraform validate

# Plan changes (DO NOT APPLY)
terraform plan -out=tfplan

# Document your changes
git commit -m "terraform: increase ECS max capacity

- Changed max_capacity from 6 to 10 tasks
- Reason: Support increased expected load
- Cost impact: ~€10/month additional"
```

### Checklist for Infrastructure Changes

- [ ] Tested locally with `terraform plan`
- [ ] No destructive changes (database deletions, etc.)
- [ ] Cost impact documented
- [ ] Security implications reviewed
- [ ] Backward compatible (if possible)

---

## Documentation Changes

### Guidelines

- Use clear, simple language
- Include examples for complex topics
- Keep docs in sync with code
- Update table of contents if adding sections
- Add links to related docs

### Structure

```markdown
# Title

## Overview
Brief explanation of what this covers

## Quick Start
Get started in 5 minutes

## Detailed Explanation
In-depth guide with examples

## Troubleshooting
Common problems and solutions

## Related Documents
Links to relevant docs
```

---

## Testing Your Changes

### Before Submitting PR

```bash
# 1. Run all tests
npm test -- --coverage

# 2. Lint code
npm run lint

# 3. Type check
npm run type-check

# 4. Test locally
npm run dev
# Manually test your changes

# 5. Build Docker image (if code changes)
docker build -t enterprise-platform:dev .

# 6. Check for security issues
npm audit

# 7. Update documentation if needed
# - Update README.md if user-facing changes
# - Update CHANGELOG.md
# - Update relevant docs/ files
```

### Testing on AWS (for Terraform changes)

```bash
# Only if infrastructure change
cd terraform

# Validate syntax
terraform validate

# Plan changes
terraform plan

# Review output carefully
# Check for:
# - Unexpected deletions
# - Resource replacements
# - Cost increases

# DO NOT terraform apply without review!
# Always have another pair of eyes
```

---

## PR Review Process

### What We Look For

✅ **Code quality**
- Follows style guide
- No unnecessary complexity
- Tests included
- Type safe

✅ **Documentation**
- Code is documented
- Docs updated if needed
- Examples provided

✅ **Testing**
- Tests pass locally
- Coverage maintained
- Edge cases tested

✅ **Performance**
- No performance regressions
- Database queries optimized
- No memory leaks

### Review Timeline

- Response within 48 hours
- Constructive feedback provided
- Iteration process is normal
- Requests for changes don't mean rejection

### Addressing Feedback

```bash
# Make requested changes
nano services/api/app.js

# Commit with message indicating it's addressing feedback
git commit -m "refactor: address PR feedback on error handling

- Simplified error message as suggested
- Added additional test case for edge case
- Updated documentation for clarity"

# Push updates
git push origin feature/your-feature-name

# No need to close and reopen PR, just push updates
```

---

## Continuous Integration

### GitHub Actions

All PRs automatically run:
- Unit tests
- Linting
- TypeScript type checking
- Docker build validation
- Terraform validation (if applicable)

**PR cannot be merged if CI fails.**

Run CI locally before pushing:
```bash
npm test && npm run lint && npm run type-check
```

---

## Documentation for Contributors

### Architecture Understanding

Before contributing significantly, understand:
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design
- [DEPLOYMENT.md](docs/DEPLOYMENT.md) - How system is deployed
- [OPERATIONS.md](docs/OPERATIONS.md) - How system is operated

### Project Structure

```
enterprise-platform/
├── services/api/          # Backend code
├── terraform/             # Infrastructure
├── docs/                  # Documentation
├── scripts/               # Utility scripts
└── .github/workflows/     # CI/CD pipeline
```

---

## Getting Help

### Questions?

- Check existing [issues](https://github.com/SilentKn1ght/enterprise-platform/issues)
- Create a new discussion if unsure
- Ask in PR comments - reviewers are happy to help

### Blocked?

- Review [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues
- Check related PRs for context
- Ask in the issue or PR - we want to help!

---

## Recognition

Contributors are recognized for their work:
- Listed in README.md (with permission)
- Mentioned in CHANGELOG.md
- Credit in commit messages

---

## Release Process

When code is ready to release:

1. **Version Bump** - Update version in package.json
2. **Changelog** - Add changes to CHANGELOG.md
3. **Tag Release** - Create git tag: `v1.0.1`
4. **Deploy** - Push tag triggers automated release

Only maintainers perform releases currently.

---

## Code of Conduct Summary

- ✅ Be respectful and inclusive
- ✅ Give constructive feedback
- ✅ Assume good intent
- ❌ No harassment or discrimination
- ❌ No spam or self-promotion

---

## License

By contributing, you agree your code is licensed under MIT License.

---

Thank you for contributing to Enterprise Platform! 🙏

**For detailed documentation:**
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design
- [DEPLOYMENT.md](docs/DEPLOYMENT.md) - Deployment guide
- [OPERATIONS.md](docs/OPERATIONS.md) - Operations guide
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Problem solving

**Questions?** Open an issue on GitHub!
