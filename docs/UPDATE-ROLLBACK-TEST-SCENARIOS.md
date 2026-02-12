# Update Pipeline Test Scenarios

This document provides step-by-step scenarios to test both successful updates and automatic rollback.

---

## Scenario 1: Successful Update (Happy Path)

This tests that the update pipeline works correctly when everything goes well.

### Prerequisites
```bash
# Start with a known working version
cd docker
docker-compose -f docker-compose.test.yml down
docker pull n8nio/n8n:1.29.0
# Edit docker-compose.test.yml to use image: n8nio/n8n:1.29.0
docker-compose -f docker-compose.test.yml up -d
```

### Steps

**1. Verify Current State**
```bash
cd ../scripts
./start-test-env.sh

# Check current version
docker exec n8n-test n8n --version
# Should show: 1.29.0 (or whatever you started with)

# Import test workflows
./import-test-workflows.sh

# Verify everything works
./test-webhooks.sh
# All tests should pass
```

**2. Run the Update Pipeline**
```bash
# Use the automated test script
./test-update-pipeline.sh 1.30.0
```

**What Happens:**
1. ✅ Backup created (image tag, database dump, volume backup)
2. ✅ Pre-update tests run (all 17 tests pass, baseline saved)
3. ✅ Update to 1.30.0 (container replaced, same data)
4. ✅ Post-update tests run (all 17 tests pass)
5. ✅ Comparison shows no regressions
6. ✅ Update kept, no rollback needed

**3. Verify Success**
```bash
# Check new version
docker exec n8n-test n8n --version
# Should show: 1.30.0

# Verify workflows still work
./test-webhooks.sh
# All tests should still pass

# Check that workflows are still there
curl -s http://localhost:5679/webhook/test/health
# Should return: {"status":"ok",...}
```

**Expected Result:** ✅ Update successful, n8n running 1.30.0, all workflows intact

---

## Scenario 2: Failed Update with Automatic Rollback

This tests that the pipeline automatically rolls back when tests fail after an update.

### Method A: Simulate Breaking Change (Recommended)

**1. Start with Working State**
```bash
cd scripts
./start-test-env.sh
./import-test-workflows.sh

# Verify current version
docker exec n8n-test n8n --version
# Note the version (e.g., 1.29.0)
```

**2. Create Backup**
```bash
./backup.sh
# Note the backup ID (e.g., 20260211_140530)
```

**3. Run Pre-Update Tests**
```bash
cd ../tests
./runner.sh --mode=update --phase=pre-update
# All tests should pass, baseline saved
```

**4. Simulate a Breaking Update**

We'll intentionally break the database connection to simulate a bad update:

```bash
# Update to a new version but break the database connection
cd ../scripts

# Stop n8n
docker stop n8n-test

# Start with wrong database host (simulates breaking change)
docker run -d \
  --name n8n-test-broken \
  --network docker_n8n-test-network \
  -p 5679:5678 \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=wrong-host \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=n8n \
  -e DB_POSTGRESDB_PASSWORD=n8n_password \
  -e N8N_ENCRYPTION_KEY=test-encryption-key \
  -v docker_n8n-test-data:/home/node/.n8n \
  n8nio/n8n:latest

# Wait a bit
sleep 10
```

**5. Run Post-Update Tests**
```bash
cd ../tests

# Update config to use the broken container
export N8N_CONTAINER=n8n-test-broken

./runner.sh --mode=update --phase=post-update
```

**What Happens:**
- ❌ INF-001: Container running - PASS (container is running)
- ❌ INF-003: PostgreSQL health - FAIL (can't connect to database)
- ❌ DB-001: Database query - FAIL (no database connection)
- ❌ WF-001: Webhook test - FAIL (n8n can't start without database)
- 🔴 **CRITICAL tests failed → Automatic rollback triggered**

**6. Execute Rollback**
```bash
cd ../scripts

# Stop broken container
docker stop n8n-test-broken
docker rm n8n-test-broken

# Rollback to previous version
BACKUP_ID=$(ls -t ../tests/state/ | head -1)
./rollback.sh "$BACKUP_ID"
```

**7. Verify Rollback Success**
```bash
# Check version is back to original
docker exec n8n-test n8n --version
# Should show: 1.29.0 (original version)

# Verify workflows work again
./test-webhooks.sh
# All tests should pass

# Check database
curl -s http://localhost:5679/webhook/test/health
# Should return: {"status":"ok",...}
```

**Expected Result:** ✅ Rollback successful, back to 1.29.0, all workflows working

---

### Method B: Simulate with Encryption Key Change (More Realistic)

This simulates a real-world scenario where the encryption key is lost/changed.

**1. Start with Working State**
```bash
cd scripts
./start-test-env.sh
./import-test-workflows.sh
```

**2. Create Backup**
```bash
./backup.sh
BACKUP_ID=$(ls -t ../tests/state/ | head -1)
echo "Backup ID: $BACKUP_ID"
```

**3. Run Pre-Update Tests**
```bash
cd ../tests
./runner.sh --mode=update --phase=pre-update
```

**4. Simulate Update with Wrong Encryption Key**
```bash
cd ../scripts

# Stop current container
docker stop n8n-test
docker rm n8n-test

# Start with WRONG encryption key (simulates lost key after update)
docker run -d \
  --name n8n-test \
  --network docker_n8n-test-network \
  -p 5679:5678 \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=n8n-postgres-test \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=n8n \
  -e DB_POSTGRESDB_PASSWORD=n8n_password \
  -e N8N_ENCRYPTION_KEY=WRONG-KEY-BREAKS-CREDENTIALS \
  -v docker_n8n-test-data:/home/node/.n8n \
  n8nio/n8n:latest

sleep 30
```

**5. Run Post-Update Tests**
```bash
cd ../tests
./runner.sh --mode=update --phase=post-update
```

**What Happens:**
- ✅ INF tests: PASS (container and database are fine)
- ✅ WEB tests: PASS (web interface loads)
- ❌ **SEC-005: Credential Encryption - FAIL** (credentials can't be decrypted)
- ❌ **CRED-001: Credential Decryption - FAIL** (CRITICAL test)
- 🔴 **CRITICAL test failed → Automatic rollback triggered**

**6. Rollback**
```bash
cd ../scripts
./rollback.sh "$BACKUP_ID"
```

**7. Verify**
```bash
# Check encryption key is restored
docker exec n8n-test env | grep N8N_ENCRYPTION_KEY
# Should show: test-encryption-key (original)

# Verify credentials work
./test-webhooks.sh
```

**Expected Result:** ✅ Rollback successful, credentials decryptable again

---

## Scenario 3: Test Rollback Decision Logic

This tests the automatic rollback decision without actually breaking anything.

**1. Setup**
```bash
cd scripts
./start-test-env.sh
./import-test-workflows.sh
```

**2. Create Fake Baseline with Good Results**
```bash
cd ../tests

# Run tests and save as baseline
./runner.sh --mode=update --phase=pre-update

# Manually edit baseline to show all tests passed
cat state/baseline.json
```

**3. Create Fake Post-Update Results with Failures**
```bash
# Run tests again but manually fail some
./runner.sh --mode=update --phase=post-update

# Manually edit results to simulate failures
# Edit tests/results/post-update-report.json
# Change some "status": "pass" to "status": "fail"
```

**4. Test Rollback Decision**
```bash
# The runner will compare and decide
# Check tests/state/rollback-decision.json

cat state/rollback-decision.json
```

Should show:
```json
{
  "rollback_needed": true,
  "reason": "Critical test failed: CRED-001",
  "failed_tests": ["CRED-001", "SEC-005"],
  "timestamp": "..."
}
```

---

## Quick Test Commands

### Test Successful Update
```bash
cd scripts
./test-update-pipeline.sh latest
# Should complete with: ✅ Update pipeline test: PASSED
```

### Force Rollback Test
```bash
cd scripts

# 1. Setup and backup
./start-test-env.sh
./import-test-workflows.sh
./backup.sh

# 2. Break something
docker exec n8n-test rm -rf /home/node/.n8n/workflows

# 3. Run post-update tests (will fail)
cd ../tests
./runner.sh --mode=update --phase=post-update

# 4. Rollback
cd ../scripts
BACKUP_ID=$(ls -t ../tests/state/ | head -1)
./rollback.sh "$BACKUP_ID"

# 5. Verify restoration
./test-webhooks.sh
```

---

## Rollback Triggers

The pipeline automatically triggers rollback if **ANY** of these conditions are met:

1. **Critical Test Fails** (P0 priority)
   - INF-001: Container not running
   - INF-003: Database not healthy
   - DB-001: Database query fails
   - SEC-005: Credentials can't be decrypted
   - CRED-001: Credential decryption fails

2. **Too Many Failures** (>30% of all tests fail)
   - If 6 or more tests fail out of 17

3. **Performance Regression**
   - Response time increased > 50%
   - Memory usage increased > 100%

4. **Data Loss**
   - Workflow count dropped to 0
   - Credential count dropped to 0

---

## Verification Checklist

After any test, verify:

- [ ] Container is running: `docker ps | grep n8n-test`
- [ ] Correct version: `docker exec n8n-test n8n --version`
- [ ] Database accessible: `docker exec n8n-postgres-test psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;"`
- [ ] Workflows work: `curl http://localhost:5679/webhook/test/health`
- [ ] Web interface loads: `curl -I http://localhost:5679`
- [ ] Backup exists: `ls -lh tests/state/`

---

## Troubleshooting

### Rollback doesn't restore workflows
**Cause:** Database wasn't backed up properly

**Fix:**
```bash
# Check if database backup exists
ls -lh tests/state/*/database.sql.gz

# Manually restore
BACKUP_ID=<your-backup-id>
zcat tests/state/$BACKUP_ID/database.sql.gz | \
  docker exec -i n8n-postgres-test psql -U n8n -d n8n
```

### Container won't start after rollback
**Cause:** Volume or network issue

**Fix:**
```bash
# Check logs
docker logs n8n-test --tail 50

# Restart from scratch
docker-compose -f docker/docker-compose.test.yml down
docker-compose -f docker/docker-compose.test.yml up -d
```

### Tests pass but workflows don't work
**Cause:** Workflows not imported

**Fix:**
```bash
cd scripts
./import-test-workflows.sh
```

---

## Summary

- **Scenario 1:** Tests successful update (version upgrade, all tests pass)
- **Scenario 2:** Tests automatic rollback (simulate breaking change)
- **Scenario 3:** Tests rollback decision logic (manual result manipulation)

Use these scenarios to validate your update pipeline before relying on it in production!
