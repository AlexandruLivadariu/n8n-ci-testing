# Test Scripts - Quick Reference

## Fully Automated Scripts

### 🚀 run-full-test.sh
**Complete automated test run** - Does everything automatically:
1. Starts test environment (n8n + PostgreSQL)
2. Imports test workflows (if API key available)
3. Runs webhook tests
4. Runs full test suite

```bash
cd scripts
chmod +x run-full-test.sh
./run-full-test.sh
```

**Requirements:** Docker and docker-compose installed
**Optional:** Set `N8N_TEST_API_KEY` for automatic workflow import

---

### ⚡ quick-test.sh
**Quick test run** - Assumes environment is already running:
- Detects running instance (test or dev)
- Runs health check tests
- Fast execution

```bash
cd scripts
chmod +x quick-test.sh
./quick-test.sh
```

**Requirements:** n8n-test or n8n-dev must be running

---

## Environment Management

### start-test-env.sh
Start test environment and wait until ready:
```bash
cd scripts
chmod +x start-test-env.sh
./start-test-env.sh
```

### stop-test-env.sh
Stop test environment:
```bash
cd scripts
chmod +x stop-test-env.sh
./stop-test-env.sh
```

---

## Individual Test Scripts

### test-webhooks.sh
Run webhook-based tests:
```bash
cd scripts
chmod +x test-webhooks.sh
./test-webhooks.sh
```

### import-test-workflows.sh
Import test workflows to n8n:
```bash
export N8N_TEST_API_KEY="your-api-key"
cd scripts
chmod +x import-test-workflows.sh
./import-test-workflows.sh
```

---

## Update & Maintenance Scripts

### update.sh
Update n8n to a new version:
```bash
cd scripts
chmod +x update.sh
./update.sh latest
```

### backup.sh
Create backup of n8n data:
```bash
cd scripts
chmod +x backup.sh
./backup.sh
```

### rollback.sh
Rollback to previous backup:
```bash
cd scripts
chmod +x rollback.sh
./rollback.sh TIMESTAMP
```

---

## Recommended Workflow

### First Time Setup
```bash
# 1. Run full automated test
cd scripts
./run-full-test.sh

# 2. If workflow import fails, import manually:
#    - Go to http://localhost:5679
#    - Import workflows from /workflows directory
#    - Activate each workflow

# 3. Run tests again
./run-full-test.sh
```

### Daily Testing
```bash
# Quick test (if environment already running)
cd scripts
./quick-test.sh

# Or full test (starts fresh environment)
./run-full-test.sh
```

### CI/CD (GitHub Actions)
The workflows automatically handle everything:
- `test-workflows.yml` - Runs on push/PR
- `health-check-pipeline.yml` - Manual or scheduled
- `update-pipeline.yml` - Manual update with rollback

---

## Environment Variables

### Required for API operations:
```bash
export N8N_TEST_API_KEY="your-api-key-here"
```

### Optional:
```bash
export N8N_HOST="http://localhost:5679"  # Default
export N8N_DB_PASSWORD="your-db-password"
```

### For corporate proxies:
```bash
export NO_PROXY="localhost,127.0.0.1"
```
(Already set automatically in scripts)

---

## Troubleshooting

### "Container not found"
```bash
# Start test environment first
cd scripts
./start-test-env.sh
```

### "API key unauthorized"
```bash
# Get API key from n8n:
# 1. Go to http://localhost:5679
# 2. Settings → API → Create API Key
# 3. Export it:
export N8N_TEST_API_KEY="n8n_api_..."
```

### "Port already in use"
```bash
# Stop existing instance
cd scripts
./stop-test-env.sh

# Or check what's using the port
docker ps | grep 5679
```

### Tests fail but containers are running
```bash
# Check container logs
docker logs n8n-test --tail 50

# Check if n8n is responding
curl http://localhost:5679

# Restart environment
cd scripts
./stop-test-env.sh
./start-test-env.sh
```

---

## Script Execution Order

**Full automated test:**
```
run-full-test.sh
  ├─> start-test-env.sh
  ├─> import-test-workflows.sh (optional)
  ├─> test-webhooks.sh
  └─> tests/runner.sh
```

**Quick test:**
```
quick-test.sh
  └─> tests/runner.sh
```
