# Testing the Update Pipeline

## Overview

The update pipeline performs a complete update cycle with automatic rollback on failure:
1. Creates backup
2. Runs pre-update tests (baseline)
3. Updates n8n to target version
4. Runs post-update tests
5. Compares results
6. Rolls back if tests fail

## Local Testing

### Quick Test (Automated)

```bash
cd scripts
chmod +x test-update-pipeline.sh
./test-update-pipeline.sh
```

This will:
- Start test environment
- Import workflows
- Run baseline tests
- Create backup
- Update to latest version
- Run post-update tests
- Compare results
- Rollback if needed

### Manual Step-by-Step Test

```bash
# 1. Start test environment
cd scripts
./start-test-env.sh

# 2. Import workflows
./import-test-workflows.sh

# 3. Run pre-update tests
cd ../tests
./runner.sh health-check pre-update

# 4. Create backup
cd ../scripts
./backup.sh

# 5. Update n8n (specify version or use 'latest')
./update.sh 1.30.0

# 6. Run post-update tests
cd ../tests
./runner.sh health-check post-update

# 7. Compare results manually
cat results/pre-update-report.json
cat results/post-update-report.json

# 8. If tests failed, rollback
cd ../scripts
./rollback.sh <backup-id>
```

## Testing Specific Versions

### Test Update to Specific Version

```bash
./test-update-pipeline.sh 1.30.0
```

### Test Update from Old to New

```bash
# Start with old version
docker-compose -f docker/docker-compose.test.yml down
docker pull n8nio/n8n:1.29.0
# Edit docker-compose.test.yml to use 1.29.0
docker-compose -f docker/docker-compose.test.yml up -d

# Then test update to new version
./test-update-pipeline.sh 1.30.0
```

## Testing Rollback

### Force a Rollback Test

```bash
# 1. Start environment and create backup
./start-test-env.sh
./backup.sh

# 2. Manually break something
docker exec n8n-test rm -rf /home/node/.n8n/workflows

# 3. Run post-update tests (will fail)
cd ../tests
./runner.sh health-check post-update

# 4. Rollback
cd ../scripts
BACKUP_ID=$(ls -t ../tests/state/ | head -1)
./rollback.sh "$BACKUP_ID"

# 5. Verify restoration
./test-webhooks.sh
```

## GitHub Actions Testing

### Trigger Update Pipeline

1. Go to GitHub repository
2. Click **Actions** tab
3. Select **Update n8n Pipeline**
4. Click **Run workflow**
5. Enter target version (e.g., `1.30.0` or `latest`)
6. Click **Run**

### What Happens

The pipeline will:
1. Check for running n8n instance (must be running)
2. Create backup
3. Run pre-update tests
4. Update to target version
5. Run post-update tests
6. Compare results
7. Rollback if tests fail
8. Send email notification

### Prerequisites for GitHub Actions

The update pipeline requires:
- A running n8n instance (n8n-test or n8n-dev)
- Self-hosted runner with Docker access
- Workflows already imported

**Note:** The update pipeline is designed for updating existing instances, not for CI/CD testing from scratch. Use the test-workflows pipeline for CI/CD testing.

## Verifying Update Success

### Check Version

```bash
docker exec n8n-test n8n --version
```

### Check Workflows Still Work

```bash
cd scripts
./test-webhooks.sh
```

### Check Database

```bash
docker exec n8n-postgres-test psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;"
```

## Common Issues

### "No running n8n instance found"

**Solution:** Start the test environment first:
```bash
cd scripts
./start-test-env.sh
```

### "Update failed to start container"

**Cause:** Docker configuration issue or port conflict

**Solution:** Check logs and ensure port 5679 is available:
```bash
docker logs n8n-test
netstat -an | grep 5679
```

### "Tests fail after update"

**Expected:** The pipeline will automatically rollback

**Manual verification:**
```bash
# Check if rollback happened
docker exec n8n-test n8n --version

# Should show the old version
```

### "Rollback doesn't restore workflows"

**Cause:** Workflows are in database, not just volume

**Solution:** The rollback script restores both database and volume. Verify:
```bash
docker exec n8n-postgres-test psql -U n8n -d n8n -c "SELECT name FROM workflow_entity;"
```

## Best Practices

1. **Always test locally first** before using in production
2. **Use specific versions** instead of `latest` for production
3. **Keep backups** - they're stored in `tests/state/`
4. **Monitor logs** during update process
5. **Verify workflows** after successful update

## Production Deployment

For production use:

1. **Adapt scripts** to your deployment method (Docker Compose, Kubernetes, etc.)
2. **Configure email notifications** in the GitHub Actions workflow
3. **Set up scheduled health checks** to monitor after updates
4. **Test rollback procedure** before relying on it
5. **Document your specific deployment** steps

## Troubleshooting

### Enable Debug Mode

```bash
# Add to scripts
set -x  # Enable debug output
```

### Check All Logs

```bash
# n8n logs
docker logs n8n-test --tail 100

# PostgreSQL logs
docker logs n8n-postgres-test --tail 50

# Test results
cat tests/results/post-update-report.json | jq '.'
```

### Manual Cleanup

```bash
# Stop everything
docker-compose -f docker/docker-compose.test.yml down

# Remove volumes (WARNING: deletes data)
docker volume rm docker_n8n-test-data docker_postgres-test-data

# Start fresh
./start-test-env.sh
```

## Summary

The update pipeline provides:
- ✅ Automated backup before updates
- ✅ Pre/post-update test comparison
- ✅ Automatic rollback on failure
- ✅ Version verification
- ✅ Email notifications

Test it locally first, then use it confidently in production!
