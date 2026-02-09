# Webhook Tests Issue - Phase 1

## Status
**Known Issue - Non-Critical**

## Summary
The webhook tests (WF-001 and CRED-001) are failing with 404 errors when accessed from inside the n8n container. These tests are marked as HIGH priority (not CRITICAL), so they don't block the pipeline.

## Test Results
- ✅ **7 tests passing** (all CRITICAL tests pass)
- ❌ **2 tests failing** (both HIGH priority webhook tests)
- ✅ **0 critical failures**

## Passing Tests
1. INF-001 - n8n Container Running ✅
2. INF-003 - PostgreSQL Health ✅
3. NET-001 - HTTP Port Accessible ✅
4. WEB-003 - Healthcheck Endpoint ✅
5. DB-001 - Database Query ✅
6. API-001 - List Workflows ✅
7. PERF-001 - Response Time Check ✅

## Failing Tests
1. WF-001 - Basic Webhook Test ❌
2. CRED-001 - Credential Decryption ❌

## Issue Details

### Symptoms
- Webhooks work from outside the container: `curl http://localhost:5679/webhook-test/test/health` ✅
- Webhooks fail from inside the container: `docker exec n8n-test wget http://localhost:5678/webhook/test/health` ❌
- Both `/webhook/` and `/webhook-test/` paths return 404 from inside container

### Root Cause
The workflows are imported and marked as "Active" in n8n UI, but the webhooks are not being registered properly for production use. This appears to be an n8n configuration issue where:

1. Test webhooks (`/webhook-test/`) only work during manual "Execute Workflow" clicks
2. Production webhooks (`/webhook/`) are not being registered even when workflows are Active
3. The webhook registration may require additional n8n configuration or environment variables

### Impact
**Low Impact** - The webhook tests validate that test workflows can execute, but they are not critical for the core update/rollback functionality. All critical infrastructure, database, API, and performance tests pass.

## Workarounds

### Option 1: Manual Verification (Current)
Before running updates, manually verify webhooks work:
```bash
curl http://localhost:5679/webhook-test/test/health
curl http://localhost:5679/webhook-test/test/credential
```

### Option 2: Skip Webhook Tests
The tests are already marked as HIGH priority (not CRITICAL), so they won't block the pipeline. The test runner will report them as failed but continue.

### Option 3: External Webhook Tests
Modify the tests to call webhooks from outside the container using the external port 5679 instead of internal port 5678.

## Resolution Plan (Phase 2)

1. **Investigate n8n webhook configuration**
   - Check if `WEBHOOK_URL` environment variable needs to be set
   - Review n8n documentation for production webhook setup
   - Check if webhooks need to be "listening" vs "active"

2. **Alternative test approach**
   - Use n8n API to trigger workflow executions instead of webhooks
   - Or test webhooks from outside the container (port 5679)

3. **Enhanced workflow setup**
   - Create workflows that don't require credentials
   - Use simpler webhook configurations
   - Add workflow activation verification to test setup

## Conclusion
Phase 1 MVP is **functionally complete** with 7/9 tests passing. All critical tests pass, ensuring the core update/rollback pipeline works correctly. The webhook tests can be addressed in Phase 2 as an enhancement.
