# Quick Command Reference

## 🚀 Start Here - Fully Automated

### Option 1: Full Automated Test (Recommended)
```bash
cd scripts
chmod +x run-full-test.sh
./run-full-test.sh
```
**Does everything automatically:**
- Starts test environment
- Imports workflows (if API key set)
- Runs all tests
- Shows results

### Option 2: Quick Test (Environment Already Running)
```bash
cd scripts
chmod +x quick-test.sh
./quick-test.sh
```

---

## 📋 Manual Step-by-Step (If Needed)

### 1. Start Test Environment
```bash
cd scripts
chmod +x start-test-env.sh
./start-test-env.sh
```

### 2. Import Workflows (Optional)
```bash
export N8N_TEST_API_KEY="your-api-key"
cd scripts
chmod +x import-test-workflows.sh
./import-test-workflows.sh
```

### 3. Run Tests
```bash
cd tests
./runner.sh --mode=health-check
```

---

## 📋 Essential Commands

### Check Status
```bash
# Are containers running?
docker ps | grep n8n

# Is n8n responding?
curl http://localhost:5679

# Is database healthy?
docker exec n8n-postgres-test pg_isready -U n8n
```

### Run Tests
```bash
cd /mnt/c/n8n-ci-testing/tests

# Health check
./runner.sh --mode=health-check

# Pre-update test
./runner.sh --mode=update --phase=pre-update

# Post-update test
./runner.sh --mode=update --phase=post-update
```

### Backup & Rollback
```bash
cd /mnt/c/n8n-ci-testing/scripts

# Create backup
./backup.sh
# Note the timestamp!

# Rollback (use timestamp from backup)
./rollback.sh 20260209_143000

# Update to new version
./update.sh latest
```

### Test Webhooks
```bash
# Health
curl http://localhost:5679/webhook-test/test/health

# Echo
curl -X POST -H "Content-Type: application/json" \
  -d '{"input":"test"}' \
  http://localhost:5679/webhook-test/test/echo

# HTTP Request
curl http://localhost:5679/webhook-test/test/http

# Credential
curl http://localhost:5679/webhook-test/test/credential
```

### View Results
```bash
# Latest test report
cd /mnt/c/n8n-ci-testing/tests
ls -lt results/ | head -5

# View with jq (if installed)
cat results/test_report_*.json | jq .

# View without jq
cat results/test_report_*.json
```

### Container Management
```bash
# Start
cd /mnt/c/n8n-ci-testing/docker
docker-compose -f docker-compose.test.yml up -d

# Stop
docker-compose -f docker-compose.test.yml down

# Restart
docker restart n8n-test

# View logs
docker logs n8n-test --tail 50
docker logs n8n-postgres-test --tail 50
```

## 🔧 Troubleshooting

### Fix "No such file or directory"
```bash
cd /mnt/c/n8n-ci-testing/tests
mkdir -p results state
```

### Fix "Connection refused"
```bash
# Restart n8n
docker restart n8n-test

# Wait 30 seconds
sleep 30

# Test
curl http://localhost:5679
```

### Fix "Container not found"
```bash
# Start containers
cd /mnt/c/n8n-ci-testing/docker
docker-compose -f docker-compose.test.yml up -d

# Wait 2 minutes
sleep 120

# Verify
docker ps | grep n8n
```

## 📧 GitHub Actions

### Trigger Manually
1. Go to repo → Actions
2. Select workflow (Update Pipeline or Health Check)
3. Click "Run workflow"
4. Fill inputs (if any)
5. Click "Run workflow"

### Check Runner Status
```bash
# In your runner folder
./run.sh
```

Or check in GitHub: Settings → Actions → Runners

## 📊 What Success Looks Like

### Health Check Output:
```
✅ Phase 1: Infrastructure Tests (2/2 passed)
✅ Phase 2: Network Tests (1/1 passed)
✅ Phase 3: Web Tests (1/1 passed)
✅ Phase 4: Database Tests (1/1 passed)
✅ Phase 5: API Tests (1/1 passed)
✅ Phase 6: Workflow Tests (1/1 passed)
✅ Phase 7: Credential Tests (1/1 passed)
✅ Phase 8: Performance Tests (1/1 passed)

Total: 10/10 tests passed
```

### Webhook Response:
```json
{
  "status": "ok",
  "timestamp": "2026-02-09T10:30:00Z",
  "test": "health_check"
}
```

### Backup Output:
```
✅ Tagged image: n8nio/n8n:latest-backup-20260209_143000
✅ Database dumped: 2.3M
✅ Volume backed up: 156K
✅ Manifest created
✅ Backup verification passed

Backup location: /tmp/n8n-backups/20260209_143000
```

## 🎯 Daily Workflow

### Morning Check:
```bash
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=health-check
```

### Before Update:
```bash
cd /mnt/c/n8n-ci-testing/scripts
./backup.sh
# Note timestamp!
```

### After Update:
```bash
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=update --phase=post-update
```

### If Something Breaks:
```bash
cd /mnt/c/n8n-ci-testing/scripts
./rollback.sh <timestamp>
```

---

**Pro Tip**: Bookmark this file for quick reference!
