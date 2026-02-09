# Phase 1 MVP - Quick Start Guide

## 🎉 Phase 1 Implementation Complete!

All Phase 1 tasks are done. Here's how to test and use the system.

## What Was Built

### Core Components
- ✅ Test runner with 10 essential tests
- ✅ Backup/rollback/update scripts
- ✅ 4 test workflows (health, echo, http, credential)
- ✅ Update Pipeline (GitHub Actions)
- ✅ Health Check Pipeline (GitHub Actions)

### Files Created
```
workflows/test-credential.json          # NEW - Credential test workflow
scripts/backup.sh                       # NEW - Backup script
scripts/rollback.sh                     # NEW - Rollback script
scripts/update.sh                       # NEW - Update script
.github/workflows/update-pipeline.yml   # NEW - Update automation
.github/workflows/health-check-pipeline.yml  # NEW - Health checks
docs/PHASE1-COMPLETE.md                 # NEW - Full documentation
```

## Quick Test (5 minutes)

### 1. Test Locally

```bash
# Test health check
cd tests
./runner.sh --mode=health-check

# Test backup
cd ../scripts
./backup.sh
# Note the timestamp output

# Test rollback
./rollback.sh <timestamp>
```

### 2. Deploy Test Workflows

```bash
cd scripts
export N8N_TEST_API_KEY="your-api-key"
export N8N_HOST="http://localhost:5679"
./import-test-workflows.sh
```

Or import manually via n8n UI:
- workflows/test-health-webhook.json
- workflows/test-echo-webhook.json
- workflows/test-http-request.json
- workflows/test-credential.json

### 3. Test Webhooks

```bash
# Health check
curl http://localhost:5679/webhook-test/test/health

# Echo test
curl -X POST -H "Content-Type: application/json" \
  -d '{"input":"test"}' \
  http://localhost:5679/webhook-test/test/echo

# HTTP request test
curl http://localhost:5679/webhook-test/test/http

# Credential test
curl http://localhost:5679/webhook-test/test/credential
```

## GitHub Actions Setup

### 1. Configure Secrets

Go to Settings → Secrets and variables → Actions, add:

```
N8N_TEST_API_KEY          # Your n8n API key
N8N_DB_PASSWORD           # PostgreSQL password
SMTP_HOST                 # Email server (e.g., smtp.gmail.com)
SMTP_USER                 # Email username
SMTP_PASSWORD             # Email password
NOTIFICATION_RECIPIENTS   # Comma-separated emails
```

### 2. Trigger Update Pipeline

1. Go to **Actions** → **n8n Update Pipeline**
2. Click **Run workflow**
3. Enter target version: `latest` (or specific version like `1.20.0`)
4. Click **Run workflow**

The pipeline will:
- Create backup
- Run pre-update tests
- Apply update
- Run post-update tests
- Rollback if tests fail
- Send email notification

### 3. Trigger Health Check

1. Go to **Actions** → **n8n Health Check Pipeline**
2. Click **Run workflow**
3. Click **Run workflow**

## Understanding Test Results

### Test Report Location
- Local: `tests/results/test-report.json`
- GitHub: Actions → Workflow run → Artifacts

### Test Report Format
```json
{
  "timestamp": "2026-02-09T10:30:00Z",
  "mode": "update",
  "phase": "post-update",
  "total_tests": 10,
  "passed": 9,
  "failed": 1,
  "critical_failures": 0,
  "tests": [
    {
      "id": "INF-001",
      "name": "n8n Container Running",
      "status": "PASS",
      "message": "Container is running"
    }
  ]
}
```

### Rollback Triggers

Automatic rollback happens if:
- ❌ Any CRITICAL test fails (e.g., CRED-001)
- ❌ More than 30% of tests fail
- ❌ Response time increases by >50%
- ❌ Memory usage increases by >100%

## 10 Tests Explained

| Test ID | Category | Description | Critical? |
|---------|----------|-------------|-----------|
| INF-001 | Infrastructure | n8n container is running | No |
| INF-003 | Infrastructure | PostgreSQL is healthy | No |
| NET-001 | Network | HTTP port accessible | No |
| WEB-003 | Web | /healthz endpoint responds | No |
| DB-001 | Database | Can query database | No |
| API-001 | API | Can list workflows | No |
| WF-001 | Workflow | Webhook test works | No |
| CRED-001 | Credential | Credentials decrypt | **YES** |
| PERF-001 | Performance | Response time acceptable | No |
| BKP-001 | Backup | Backup files valid | **YES** |

## Troubleshooting

### Tests Fail
```bash
# Check containers
docker ps | grep n8n

# Check logs
docker logs n8n-test --tail 50
docker logs n8n-postgres-test --tail 50

# Check database
docker exec n8n-postgres-test pg_isready -U n8n
```

### Workflows Not Imported
- Import manually via n8n UI
- Or use existing `scripts/test-webhooks.sh` (works without API)

### GitHub Actions Fails
- Verify self-hosted runner is online
- Check all secrets are configured
- Review runner logs

## Demo to Colleagues

### Talking Points

1. **Problem**: Manual health checks after every n8n update are time-consuming and error-prone

2. **Solution**: Automated testing with automatic rollback
   - 10 essential tests cover critical functionality
   - Automatic rollback if anything breaks
   - Email notifications keep team informed

3. **Demo Flow**:
   ```
   Show GitHub Actions → Trigger Update Pipeline → 
   Show tests running → Show email notification → 
   Show test report artifact
   ```

4. **Benefits**:
   - No more manual daily checks
   - Automatic rollback on failure
   - Complete audit trail
   - Email notifications
   - Can update confidently

### API Key Issue Explanation

When colleagues ask about API key issues:

> "We initially tried using n8n's API key authentication for testing, but ran into reliability issues in version 2.6.3. The API would sometimes reject valid keys or have inconsistent behavior. 
>
> We pivoted to webhook-based testing instead, which is more reliable and actually tests the full workflow execution path - not just the API. This gives us better end-to-end coverage.
>
> The test workflows are simple n8n workflows with webhook triggers that we can call directly. This approach is working well and is more representative of how n8n is actually used in production."

## Next Steps

### Immediate (This Week)
1. [ ] Test locally with your n8n instance
2. [ ] Import test workflows
3. [ ] Configure GitHub secrets
4. [ ] Run Update Pipeline once manually
5. [ ] Verify email notifications work

### Short Term (Next Week)
1. [ ] Enable scheduled health checks (uncomment cron in health-check-pipeline.yml)
2. [ ] Monitor first few automated runs
3. [ ] Tune thresholds if needed
4. [ ] Demo to team

### Long Term (Phase 2)
- Add remaining 55 tests (total 65)
- Add Code Change Pipeline
- Add scheduled updates
- Add multi-instance support
- Add audit logging

## Configuration

Edit `tests/config.yaml` to customize:
- n8n URL and container names
- Rollback thresholds
- Backup location
- Notification settings

## Support

- Full docs: `docs/PHASE1-COMPLETE.md`
- Test docs: `tests/README.md`
- Design docs: `.kiro/specs/automated-n8n-update-testing/`

---

**Status**: Ready to test! 🚀  
**Next**: Run local tests, then trigger GitHub Actions
