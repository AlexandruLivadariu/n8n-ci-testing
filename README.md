# n8n Automated Testing & Update System

Complete automated testing and update management system for n8n enterprise deployments. Includes automated rollback, health monitoring, and CI/CD pipelines.

## 🚀 Quick Start

### One Command Test
```bash
./test.sh
```

This automatically starts the environment, imports workflows, runs all tests, and shows results.

---

## What This System Does

This project provides a complete automation solution for n8n deployments:

- **Automated Testing**: 15+ tests covering infrastructure, security, workflows, and performance
- **Update Management**: Automated version updates with pre/post validation
- **Automatic Rollback**: Rolls back failed updates automatically
- **Health Monitoring**: Scheduled health checks with alerts
- **CI/CD Pipelines**: GitHub Actions workflows for automation
- **Backup/Restore**: Automated backup before updates with one-command restore

---

## Architecture

### Environments
- **n8n-dev** (port 5678): Development environment for creating workflows
- **n8n-test** (port 5679): Isolated test environment for validation
- Separate PostgreSQL databases for each
- Persistent encryption keys for credential stability

### Test Categories (15 Tests)
1. **Infrastructure** (6 tests): Container health, uptime, PostgreSQL, network, volumes, resources
2. **Network & Web** (2 tests): HTTP accessibility, healthcheck endpoint
3. **Database & API** (2 tests): Database queries, API functionality
4. **Workflows** (1 test): Webhook execution
5. **Credentials** (1 test): Credential decryption
6. **Performance** (1 test): Response time monitoring
7. **Security** (5 tests): Headers, authentication, container security, environment vars, encryption
8. **Backup** (1 test): Backup verification

### Automation Scripts
- **Testing**: `run-full-test.sh`, `test-webhooks.sh`, `runner.sh`
- **Updates**: `update.sh`, `backup.sh`, `rollback.sh`
- **Environment**: `start-test-env.sh`, `stop-test-env.sh`
- **Workflows**: `import-test-workflows.sh`, `export-workflows.sh`

### CI/CD Pipelines
- **Update Pipeline**: Automated updates with rollback on failure
- **Health Check Pipeline**: Scheduled monitoring with alerts
- **Test Workflows**: CI/CD testing on code changes

---

## Prerequisites

- Docker and Docker Compose
- `curl` and `jq` (usually pre-installed)
- Git (for CI/CD)
- WSL/Linux (recommended for production)

---

## How to Use

### 1. Local Testing

```bash
# Full automated test
./test.sh

# Or step by step
cd scripts
./start-test-env.sh          # Start environment
./import-test-workflows.sh   # Import test workflows (optional)
cd ../tests
./runner.sh --mode=health-check  # Run tests
```

### 2. Manual Update with Rollback

```bash
cd scripts

# Create backup
./backup.sh
# Note the timestamp: 20260216_143000

# Update to new version
./update.sh latest

# If something breaks, rollback
./rollback.sh 20260216_143000
```

### 3. Automated Update via GitHub Actions

1. Go to **Actions** → **n8n Update Pipeline**
2. Click **Run workflow**
3. Enter target version (e.g., `latest` or `1.30.0`)
4. Click **Run workflow**

The pipeline will:
- Create backup automatically
- Run pre-update tests (baseline)
- Apply update
- Run post-update tests
- **Automatically rollback** if tests fail
- Send email notification

### 4. Health Monitoring

```bash
# Manual health check
cd tests
./runner.sh --mode=health-check

# Or via GitHub Actions
# Go to Actions → n8n Health Check Pipeline → Run workflow
```

---

## Test Results

### What Gets Tested

**Infrastructure Tests (Critical)**
- Container running and healthy
- Container uptime stability (no crash loops)
- PostgreSQL connectivity
- Network connectivity between containers
- Volume mounts and write access
- Resource usage (CPU/memory)

**Network & Web Tests (Critical)**
- HTTP port accessible
- Healthcheck endpoint responding

**Database & API Tests (Critical)**
- Database queries working
- API endpoints accessible

**Workflow Tests**
- Webhook execution
- Data processing

**Credential Tests**
- Credential decryption (detects encryption key issues)

**Performance Tests**
- Response time monitoring
- Baseline comparison

**Security Tests**
- Security headers (X-Content-Type-Options, X-Frame-Options)
- Unauthenticated access prevention
- Container security configuration
- Environment variable integrity
- Credential encryption

**Backup Tests**
- Backup file verification

### Test Results Location

```bash
# Latest results
cat tests/results/latest.json | jq .

# All results
ls -lt tests/results/

# View summary
cat tests/results/test_report_*.json | jq '.summary'
```

### Success Criteria

Tests pass if:
- All CRITICAL tests pass
- Less than 30% of tests fail
- Response time increase < 50%
- Memory increase < 100%

**Automatic rollback triggers if:**
- Any CRITICAL test fails
- More than 30% of tests fail
- Response time increases > 50%
- Memory usage increases > 100%

---

## Configuration

### Test Configuration (`tests/config.yaml`)

```yaml
n8n:
  url: "http://localhost:5679"
  container_name: "n8n-test"

thresholds:
  critical_test_failure: true
  test_failure_percent: 30
  response_time_increase_percent: 50
  memory_increase_percent: 100
  container_startup_timeout_seconds: 120

backup:
  directory: "/tmp/n8n-backups"
  retention_days: 30
```

### Docker Configuration

**Test Environment** (`docker/docker-compose.test.yml`)
- n8n version: 1.29.0 (for testing updates)
- Port: 5679
- Database: n8n-postgres-test

**Dev Environment** (`docker/docker-compose.dev.yml`)
- n8n version: latest
- Port: 5678
- Database: n8n-postgres-dev

---

## GitHub Actions Setup

### 1. Configure Secrets

Go to **Settings** → **Secrets and variables** → **Actions**

Required secrets:
```
N8N_TEST_API_KEY          # n8n API key (optional for workflow import)
N8N_DB_PASSWORD           # PostgreSQL password
SMTP_HOST                 # Email server (e.g., smtp.gmail.com)
SMTP_USER                 # Email username
SMTP_PASSWORD             # Email password
NOTIFICATION_RECIPIENTS   # Comma-separated emails
```

### 2. Set Up Self-Hosted Runner

```bash
# Download and configure runner
# (Follow GitHub's instructions in Settings → Actions → Runners)

# Start runner
./run.sh
```

### 3. Enable Scheduled Health Checks

Edit `.github/workflows/health-check-pipeline.yml`:

```yaml
on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8 AM
```

---

## How It Works

### Update Flow

```
1. TRIGGER (Manual or Scheduled)
   └─> GitHub Actions: update-pipeline.yml

2. PRE-UPDATE
   ├─> Create timestamped backup
   ├─> Run baseline tests
   └─> Save results

3. UPDATE
   ├─> Pull new n8n version
   ├─> Stop old container
   ├─> Start new container
   └─> Wait for health

4. POST-UPDATE
   ├─> Run validation tests
   ├─> Compare with baseline
   └─> Make rollback decision

5. DECISION
   ├─> Tests Pass → SUCCESS
   │   └─> Send success notification
   └─> Tests Fail → ROLLBACK
       ├─> Restore from backup
       ├─> Verify rollback
       └─> Send failure notification
```

### Rollback Decision Logic

```python
if critical_test_failure:
    rollback = True
elif test_failure_percent > 30%:
    rollback = True
elif response_time_increase > 50%:
    rollback = True
elif memory_increase > 100%:
    rollback = True
else:
    rollback = False
```

---

## Troubleshooting

### Corporate Proxy Issues

```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
```

### Container Not Starting

```bash
# Check logs
docker logs n8n-test --tail 50

# Restart
docker restart n8n-test

# Full reset
cd docker
docker-compose -f docker-compose.test.yml down -v
docker-compose -f docker-compose.test.yml up -d
```

### Tests Failing

```bash
# Check container status
docker ps | grep n8n

# Check database
docker exec n8n-postgres-test pg_isready -U n8n

# Check n8n logs
docker logs n8n-test --tail 100

# Run specific test
cd tests
./runner.sh --mode=health-check
```

### Workflows Not Working

```bash
# Import workflows manually
cd scripts
export N8N_TEST_API_KEY="your-key"
./import-test-workflows.sh

# Or import via UI
# Go to http://localhost:5679
# Import from workflows/ folder
# Activate each workflow
```

---

## Key Features

### Automated Rollback
- Automatic backup before every update
- Rollback decision based on test results
- One-command manual rollback: `./rollback.sh <timestamp>`

### Health Monitoring
- 15+ automated tests
- Scheduled health checks
- Email notifications
- Test result artifacts

### Security Testing
- Security headers validation
- Authentication checks
- Container security audit
- Credential encryption verification

### Performance Monitoring
- Response time tracking
- Memory usage monitoring
- Baseline comparison
- Regression detection

---

## Project Structure

```
.
├── docker/                    # Docker Compose files
│   ├── docker-compose.dev.yml
│   └── docker-compose.test.yml
├── scripts/                   # Automation scripts
│   ├── backup.sh
│   ├── rollback.sh
│   ├── update.sh
│   ├── run-full-test.sh
│   └── ...
├── tests/                     # Test framework
│   ├── runner.sh             # Main test runner
│   ├── config.yaml           # Test configuration
│   └── lib/                  # Test libraries
│       ├── inf-tests.sh      # Infrastructure tests
│       ├── sec-tests.sh      # Security tests
│       ├── wf-tests.sh       # Workflow tests
│       └── ...
├── .github/workflows/         # CI/CD pipelines
│   ├── update-pipeline.yml
│   ├── health-check-pipeline.yml
│   └── test-workflows.yml
├── workflows/                 # Test workflows
│   ├── test-health-webhook.json
│   ├── test-http-request.json
│   └── ...
└── README.md                  # This file
```

---

## Next Steps

1. **Test locally**: Run `./test.sh` to verify everything works
2. **Configure GitHub**: Set up secrets and self-hosted runner
3. **Test update pipeline**: Trigger manual update via GitHub Actions
4. **Enable monitoring**: Uncomment cron schedule in health-check-pipeline.yml
5. **Production deployment**: Update backup directory and SMTP settings

---

## Documentation

- `QUICK-COMMANDS.md` - Command reference
- `docs/IMPLEMENTATION-SUMMARY.md` - Detailed implementation guide
- `tests/README.md` - Test framework documentation
- `scripts/README.md` - Script reference

---

## Support

For issues or questions:
1. Check logs: `docker logs n8n-test`
2. Review test results: `cat tests/results/latest.json | jq .`
3. Check documentation in `docs/` folder

---

**Status**: Production ready ✅  
**Test Coverage**: 15 automated tests  
**Automation**: Full CI/CD with automatic rollback
