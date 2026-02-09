# Simple Step-by-Step Testing Guide

## Prerequisites Check

Before testing, you need:
- ✅ n8n test instance running (Docker containers)
- ✅ GitHub self-hosted runner (can be in another folder - that's fine!)

## Step 1: Start n8n Test Instance (If Not Running)

### Check if n8n is already running:
```bash
docker ps | grep n8n-test
```

### If NOT running, start it:
```bash
cd /mnt/c/n8n-ci-testing/docker
docker-compose -f docker-compose.test.yml up -d
```

### Wait for it to be ready (2-3 minutes):
```bash
# Check containers are up
docker ps | grep n8n

# Check n8n is responding
curl http://localhost:5679
```

You should see HTML output from n8n.

## Step 2: Fix Zscaler Proxy Issue

Your Zscaler proxy is blocking localhost. Fix it:

```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
```

### Test the fix:
```bash
curl http://localhost:5679
```

You should see HTML (not Zscaler error page).

### Make it permanent (optional):
```bash
echo 'export no_proxy="localhost,127.0.0.1"' >> ~/.bashrc
echo 'export NO_PROXY="localhost,127.0.0.1"' >> ~/.bashrc
source ~/.bashrc
```

See `PROXY-FIX.md` for more details.

## Step 3: Create Required Directories

```bash
cd /mnt/c/n8n-ci-testing/tests
mkdir -p results state
```

## Step 3: Create Required Directories

```bash
cd /mnt/c/n8n-ci-testing/tests
mkdir -p results state
```

## Step 4: Run Health Check Test (Easy Way)

```bash
cd /mnt/c/n8n-ci-testing/tests
./quick-test.sh
```

This script automatically:
- Sets proxy bypass
- Creates directories
- Runs health check
- Shows results

### Or run manually:
```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=health-check
```

### What to expect:
- You'll see colored output showing each test
- Tests will run in phases
- At the end, you'll see a summary
- Results saved to `results/test_report_*.json`

### If it fails:
```bash
# 1. Fix proxy
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

# 2. Check n8n is running
docker ps | grep n8n-test

# Check n8n responds
curl http://localhost:5679

# Check database
docker exec n8n-postgres-test pg_isready -U n8n
```

## Step 4: Import Test Workflows

### Option A: Via n8n UI (Recommended - More Reliable)

1. Open browser: http://localhost:5679
2. Click "Add workflow" → "Import from file"
3. Import these 4 files one by one:
   - `/mnt/c/n8n-ci-testing/workflows/test-health-webhook.json`
   - `/mnt/c/n8n-ci-testing/workflows/test-echo-webhook.json`
   - `/mnt/c/n8n-ci-testing/workflows/test-http-request.json`
   - `/mnt/c/n8n-ci-testing/workflows/test-credential.json`
4. Make sure each workflow is **ACTIVE** (toggle in top right)

### Option B: Via Script (If you have API key)

```bash
cd /mnt/c/n8n-ci-testing/scripts
export N8N_TEST_API_KEY="your-api-key-here"
export N8N_HOST="http://localhost:5679"
./import-test-workflows.sh
```

## Step 5: Test Webhooks Manually

```bash
# Test 1: Health check
curl http://localhost:5679/webhook-test/test/health

# Test 2: Echo (data processing)
curl -X POST -H "Content-Type: application/json" \
  -d '{"input":"hello"}' \
  http://localhost:5679/webhook-test/test/echo

# Test 3: HTTP request
curl http://localhost:5679/webhook-test/test/http

# Test 4: Credential test
curl http://localhost:5679/webhook-test/test/credential
```

Each should return JSON with `"success":true` or similar.

## Step 6: Run Health Check Again

Now that workflows are imported:

```bash
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=health-check
```

All 10 tests should pass now!

## Step 7: Test Backup Script

```bash
cd /mnt/c/n8n-ci-testing/scripts
./backup.sh
```

### What to expect:
- Creates backup in `/tmp/n8n-backups/`
- Shows timestamp (e.g., `20260209_143000`)
- Creates Docker image tag, DB dump, manifest

### Check backup was created:
```bash
ls -la /tmp/n8n-backups/
```

You should see a folder with timestamp.

## Step 8: Test Rollback Script

```bash
cd /mnt/c/n8n-ci-testing/scripts

# Use the timestamp from Step 7
./rollback.sh 20260209_143000
```

### What to expect:
- Stops n8n
- Restores database
- Starts n8n with backup image
- Waits for health check

### Verify n8n is back:
```bash
curl http://localhost:5679
```

## Step 9: Configure GitHub Secrets

Your self-hosted runner is in another folder - that's perfect! Now configure secrets:

1. Go to your GitHub repo in browser
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these 6 secrets:

| Secret Name | Value | Example |
|-------------|-------|---------|
| `N8N_TEST_API_KEY` | Your n8n API key | `n8n_api_xxx...` |
| `N8N_DB_PASSWORD` | PostgreSQL password | From your .env file |
| `SMTP_HOST` | Email server | `smtp.gmail.com` |
| `SMTP_USER` | Email username | `your-email@gmail.com` |
| `SMTP_PASSWORD` | Email password | App password if using Gmail |
| `NOTIFICATION_RECIPIENTS` | Your email | `you@company.com` |

### To get n8n API key:
1. Go to http://localhost:5679
2. Click your profile (bottom left)
3. Settings → API
4. Create new API key

### To get DB password:
```bash
cat /mnt/c/n8n-ci-testing/docker/.env.test | grep POSTGRES_PASSWORD
```

## Step 10: Test GitHub Actions

### Test Health Check Pipeline:

1. Go to your repo → **Actions**
2. Click **"n8n Health Check Pipeline"** (left sidebar)
3. Click **"Run workflow"** (right side)
4. Click **"Run workflow"** (green button)
5. Watch it run (takes ~2-3 minutes)
6. Check your email for notification

### Test Update Pipeline:

1. Go to **Actions** → **"n8n Update Pipeline"**
2. Click **"Run workflow"**
3. Enter target version: `latest`
4. Leave "Skip backup" unchecked
5. Click **"Run workflow"**
6. Watch it run (takes ~5-10 minutes)
7. Check email notification

## Troubleshooting

### "No such file or directory" error
```bash
cd /mnt/c/n8n-ci-testing/tests
mkdir -p results state
```

### "Container not found" error
```bash
# Start n8n
cd /mnt/c/n8n-ci-testing/docker
docker-compose -f docker-compose.test.yml up -d

# Wait 2 minutes, then test
curl http://localhost:5679
```

### "Connection refused" error
```bash
# Check if n8n is running
docker ps | grep n8n-test

# Check logs
docker logs n8n-test --tail 50

# Restart if needed
docker restart n8n-test
```

### Webhooks return 404
- Import workflows via n8n UI (Step 4)
- Make sure workflows are ACTIVE
- Check workflow webhook paths match

### GitHub Actions fails
- Check self-hosted runner is online: Settings → Actions → Runners
- Verify all 6 secrets are configured
- Check runner has access to Docker

## Quick Reference

### Start n8n:
```bash
cd /mnt/c/n8n-ci-testing/docker
docker-compose -f docker-compose.test.yml up -d
```

### Stop n8n:
```bash
cd /mnt/c/n8n-ci-testing/docker
docker-compose -f docker-compose.test.yml down
```

### Run tests:
```bash
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=health-check
```

### View test results:
```bash
cd /mnt/c/n8n-ci-testing/tests
cat results/test_report_*.json | jq .
```

### Check n8n status:
```bash
docker ps | grep n8n
curl http://localhost:5679
```

## Success Checklist

You're ready when:
- [ ] n8n containers are running
- [ ] Health check test passes (10/10 tests)
- [ ] All 4 webhooks respond
- [ ] Backup script creates files
- [ ] Rollback script restores successfully
- [ ] GitHub secrets configured (6 secrets)
- [ ] Health Check Pipeline runs in GitHub Actions
- [ ] Update Pipeline runs in GitHub Actions
- [ ] Email notifications arrive

## Next Steps

Once all tests pass:
1. Demo to your team
2. Enable scheduled health checks (edit `.github/workflows/health-check-pipeline.yml`)
3. Use Update Pipeline when new n8n versions are released
4. Consider Phase 2 features if needed

---

**Need Help?**
- Check container logs: `docker logs n8n-test --tail 50`
- Check test results: `cat tests/results/test_report_*.json`
- Review full docs: `docs/PHASE1-COMPLETE.md`
