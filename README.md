# n8n CI/CD Testing Setup

Automated testing environment for n8n workflows using webhook-based tests. Separate dev and test instances for safe validation.

## 🚀 Quick Start (Fully Automated)

### Fastest Way - One Command
```bash
chmod +x test.sh
./test.sh
```

### Or use the full script
```bash
cd scripts
chmod +x run-full-test.sh
./run-full-test.sh
```

**This automatically:**
- Starts test environment (n8n + PostgreSQL)
- Waits for everything to be ready
- Imports test workflows (if API key set)
- Runs all tests
- Shows results

**That's it!** Everything else is handled automatically.

---

## Architecture

- **n8n-dev** (port 5678): Development environment for creating and testing workflows
- **n8n-test** (port 5679): Isolated test environment for CI/CD validation
- **Webhook-based testing**: Tests use webhooks instead of API authentication (more reliable)
- Separate PostgreSQL databases for each environment
- Persistent encryption keys to maintain API key validity across restarts

## Prerequisites

- Docker and Docker Compose
- `curl` (usually pre-installed)
- **WSL/Linux** (recommended for production-like environment)
  - If on Windows, use WSL for Linux compatibility

---

## Manual Setup (If Needed)

### 1. Start the environments

```bash
# Start test environment (automated)
cd scripts
./start-test-env.sh

# Or start dev environment
cd docker
docker-compose -f docker-compose.dev.yml up -d
```

### 2. Import test workflows (Optional)

The test workflows are webhook-based and need to be imported into n8n:

**Option A: Automated Import**
```bash
export N8N_TEST_API_KEY='your-api-key-here'
cd scripts
./import-test-workflows.sh
```

**Option B: Manual Import**
1. Go to http://localhost:5679
2. Set up owner account if prompted
3. For each workflow in `workflows/` folder:
   - Click "Add workflow" → "Import from file"
   - Select: `test-health-webhook.json`, `test-echo-webhook.json`, `test-http-request.json`
   - Click "Activate" for each workflow

### 3. Verify test workflows

Test the webhooks manually to ensure they're working:

```bash
# Bypass corporate proxy if needed
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

# Test health check
curl http://localhost:5679/webhook-test/test/health

# Test echo (data processing)
curl -X POST -H "Content-Type: application/json" \
  -d '{"input":"test"}' \
  http://localhost:5679/webhook-test/test/echo

# Test HTTP request node
curl http://localhost:5679/webhook-test/test/http
```

### 4. Run automated tests

```bash
cd scripts
./test-webhooks.sh
```

## Test Workflows

### 1. Health Check (`test-health-webhook.json`)
- **Webhook:** GET `/webhook-test/test/health`
- **Purpose:** Verify n8n can receive and respond to webhook requests
- **Response:** `{"status":"ok","timestamp":"...","test":"health_check"}`

### 2. Echo Data Processing (`test-echo-webhook.json`)
- **Webhook:** POST `/webhook-test/test/echo`
- **Purpose:** Test data processing and transformation
- **Input:** `{"input":"test_data"}`
- **Response:** `{"input":"test_data","processed_at":"...","message":"..."}`

### 3. HTTP Request Node (`test-http-request.json`)
- **Webhook:** GET `/webhook-test/test/http`
- **Purpose:** Verify n8n can make external HTTP requests
- **Response:** `{"test":"http_request","success":true,"url":"..."}`

## CI/CD Workflow

The GitHub Actions workflow (`.github/workflows/test-workflows.yml`) runs:

1. **Container Health Check**: Verify Docker containers are running
2. **Web Interface Check**: Verify n8n web UI is accessible
3. **Database Check**: Verify PostgreSQL connectivity
4. **Webhook Tests**: Test all webhook endpoints
5. **Generate Report**: Create test results summary

### Setting up CI/CD

1. **Import workflows manually** into n8n-test (port 5679) - do this once
2. **Commit and push** to trigger the workflow
3. **Tests run automatically** using webhooks (no API key needed for tests)

## Environment Variables

### For Local Testing
- `N8N_HOST`: n8n URL (default: http://localhost:5679)
- `no_proxy`: Set to "localhost,127.0.0.1" to bypass corporate proxy
- `NO_PROXY`: Set to "localhost,127.0.0.1" to bypass corporate proxy

### For Workflow Import (Optional)
- `N8N_TEST_API_KEY`: API key for test environment (only needed for automated import)

## Scripts

- `test-webhooks.sh`: Run all webhook-based tests (main test script)
- `import-test-workflows.sh`: Import test workflows via API (optional)
- `export-workflows.sh`: Export workflows from dev environment
- `import-workflows.sh`: Import workflows to test environment
- `test-api-key.sh`: Test API key authentication (for debugging)

## Important Notes

### Corporate Proxy
If you're behind a corporate proxy, set these environment variables:
```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
```

### API Key Authentication
- API key authentication is **unreliable** in n8n 2.6.3
- Tests use **webhooks instead** - more reliable and simpler
- API keys are only needed for workflow import (can be done manually)

### WSL vs Windows Docker
- **Use WSL Docker** for Linux compatibility (production is Linux)
- Windows Docker Desktop may have networking issues
- Project location: `~/n8n-ci-testing` in WSL

## Troubleshooting

**"Connection reset by peer" or proxy errors:**
- Set `no_proxy` and `NO_PROXY` environment variables
- Corporate proxy may be blocking localhost connections

**Webhooks return 404:**
- Verify workflows are imported and **activated** in n8n
- Check workflow names match exactly
- Go to http://localhost:5679 and verify workflows are active

**Containers not starting:**
- Check logs: `docker logs n8n-test`
- Verify ports 5678 and 5679 are available
- Remove old containers: `docker-compose down -v`

**Tests fail in CI but work locally:**
- Workflows may not be imported in test environment
- Import workflows manually into n8n-test (port 5679)
- Verify workflows are activated

## Test Plan

See `docs/test-plan.md` for comprehensive test strategy including:
- Infrastructure tests
- Workflow tests
- Integration tests
- Performance tests
- Security tests
- Backup and recovery tests
