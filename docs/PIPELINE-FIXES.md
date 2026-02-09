# GitHub Actions Pipeline Fixes

## Issues Fixed

### 1. Duplicate NO_PROXY Environment Variables
**Problem:** All three workflows had both `no_proxy` and `NO_PROXY` defined, causing GitHub Actions validation errors.

**Solution:** Removed lowercase `no_proxy` entries, kept only `NO_PROXY` (standard convention).

**Files Fixed:**
- `.github/workflows/health-check-pipeline.yml`
- `.github/workflows/test-workflows.yml`
- `.github/workflows/update-pipeline.yml`

### 2. Health Check Pipeline Container Mismatch
**Problem:** Health check was looking for `n8n-test` container, but should work with either dev or test instances.

**Solution:**
- Added container detection step to identify running instance (dev or test)
- Created `tests/config-dev.yaml` for dev instance health checks
- Updated `tests/runner.sh` to support `TEST_CONFIG` environment variable
- Health check now works with both `n8n-dev` and `n8n-test` containers

### 3. Test Pipeline Container Check Failure
**Problem:** Webhook test script failed immediately if n8n-test wasn't running, without proper error handling.

**Solution:**
- Updated `scripts/test-webhooks.sh` to check for both `n8n-test` and `n8n-dev` containers
- Added early exit with clear error message if no n8n instance is running
- Prevents cascade of test failures when container isn't available

### 4. Email Notification Failures
**Problem:** Health check pipeline failed when SMTP secrets weren't configured.

**Solution:**
- Made email notification step conditional (`continue-on-error: true`)
- Added fallback log notification step
- Pipeline no longer fails if SMTP isn't configured

### 5. Redundant Workflows
**Problem:** Multiple similar workflows causing confusion.

**Solution:** Disabled redundant workflows:
- `nightly-tests.yml` → `nightly-tests.yml.disabled`
- `test-n8n-update.yml` → `test-n8n-update.yml.disabled`

**Active Workflows:**
- `test-workflows.yml` - Basic workflow testing (requires n8n-test)
- `update-pipeline.yml` - Update with rollback (uses n8n-test)
- `health-check-pipeline.yml` - Health monitoring (works with dev or test)

## Usage

### Health Check Pipeline
Runs against whichever n8n instance is currently running:
```bash
# Start dev instance first
cd docker
docker-compose -f docker-compose.dev.yml up -d

# Then trigger health check from GitHub Actions UI
```

### Test Workflows Pipeline
Requires test instance (automatically started by pipeline):
```bash
# Triggered automatically on push/PR or manually from GitHub Actions UI
```

### Update Pipeline
Requires test instance and performs full update cycle:
```bash
# Triggered manually with version parameter from GitHub Actions UI
```

## Configuration Files

- `tests/config.yaml` - Test instance configuration (n8n-test)
- `tests/config-dev.yaml` - Dev instance configuration (n8n-dev)

## Re-enabling Disabled Workflows

To re-enable a disabled workflow:
```bash
cd .github/workflows
mv nightly-tests.yml.disabled nightly-tests.yml
```
