# Design Document

## Overview

This document describes the design of an automated n8n update and testing system for enterprise deployments. The system consists of three GitHub Actions pipelines that work together to detect updates, validate changes, monitor health, and automatically rollback failures.

## Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Repository                           │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  GitHub Actions Workflows                                   │ │
│  │                                                              │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │   Update     │  │ Code Change  │  │    Health    │     │ │
│  │  │   Pipeline   │  │   Pipeline   │  │    Check     │     │ │
│  │  │  (Daily 2AM) │  │  (On Push)   │  │  (Daily 8AM) │     │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │ │
│  │         │                  │                  │             │ │
│  │         └──────────────────┴──────────────────┘             │ │
│  │                            │                                │ │
│  │                            ▼                                │ │
│  │                   ┌────────────────┐                        │ │
│  │                   │  Test Runner   │                        │ │
│  │                   │   (Bash)       │                        │ │
│  │                   └────────┬───────┘                        │ │
│  └────────────────────────────┼────────────────────────────────┘ │
│                                │                                  │
│  ┌────────────────────────────┼────────────────────────────────┐ │
│  │  Test Scripts & Workflows  │                                 │ │
│  │                            │                                 │ │
│  │  /tests/runner.sh ◄────────┘                                 │ │
│  │  /tests/lib/*.sh                                             │ │
│  │  /test-workflows/*.json                                      │ │
│  │  /scripts/backup.sh, rollback.sh, update.sh                 │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Self-Hosted GitHub Runner                     │
│                    (Same host as n8n)                            │
│                                                                  │
│  - Docker access (docker.sock)                                  │
│  - Network access to n8n containers                             │
│  - Executes test scripts                                        │
│  - Manages backups and rollbacks                                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Docker Environment                            │
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │  n8n Container   │◄───────►│ PostgreSQL       │             │
│  │  Port: 5678      │         │ Container        │             │
│  │                  │         │ Port: 5432       │             │
│  │  - Test workflows│         │                  │             │
│  │  - API endpoints │         │  - n8n database  │             │
│  │  - Webhooks      │         │  - Backups       │             │
│  └──────────────────┘         └──────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

**GitHub Actions Workflows:**
- Schedule and trigger test executions
- Orchestrate update process
- Manage secrets and environment variables
- Send notifications
- Store artifacts and reports

**Test Runner (runner.sh):**
- Execute tests in correct order
- Handle test failures and continue execution
- Collect and aggregate results
- Generate JSON reports
- Make rollback decisions

**Test Library Scripts:**
- Implement individual test categories
- Use consistent output format
- Handle errors gracefully
- Support parallel execution where safe

**Backup/Rollback Scripts:**
- Create rollback points (image + DB + volume)
- Restore from rollback points
- Verify backup integrity
- Clean up old backups

**Update Script:**
- Pull new Docker images
- Stop/start containers
- Wait for health
- Handle failures

## Components

### 1. Test Runner Architecture

The test runner is the core component that executes all tests and makes decisions.



#### Test Runner Flow

```
runner.sh --mode=<update|code-change|health-check>
│
├─► Load config.yaml
├─► Initialize state (baseline, counters)
├─► Determine which tests to run based on mode
│
├─► Phase 1: Infrastructure Tests (INF-001 to INF-006)
│   │   Sequential execution, CRITICAL failures stop all tests
│   └─► If any CRITICAL test fails → Exit with failure
│
├─► Phase 2: Network & Web Tests (NET, WEB)
│   │   Sequential execution
│   └─► If any CRITICAL test fails → Exit with failure
│
├─► Phase 3: Auth & Database Tests (AUTH, DB)
│   │   Two parallel groups
│   └─► If any CRITICAL test fails → Exit with failure
│
├─► Phase 4: API & Workflow Tests (API, WF)
│   │   Sequential execution
│   └─► If any CRITICAL test fails → Exit with failure
│
├─► Phase 5: Credentials Tests (CRED)
│   │   Sequential execution, CRED-001 is CRITICAL
│   └─► If CRED-001 fails → Exit with failure
│
├─► Phase 6: Performance Tests (PERF) [Update Pipeline only]
│   │   Sequential execution
│   └─► Record metrics for comparison
│
├─► Phase 7: Backup Tests (BKP) [Update Pipeline only]
│   │   Sequential execution
│   └─► BKP-001 is CRITICAL (blocks update if fails)
│
├─► Phase 8: Security Tests (SEC)
│   │   Partially parallel
│   └─► Record findings
│
├─► Phase 9: Notification Tests (NOTIF) [Update Pipeline only]
│   │   Sequential execution
│   └─► Verify alert channels work
│
├─► Phase 10: Environment Tests (ENV) [Update Pipeline only, if multi-instance]
│   │   Sequential execution
│   └─► Compare environments
│
├─► Aggregate Results
│   ├─► Count: total, passed, failed, skipped, critical_failed
│   ├─► Calculate: failure_percentage, response_time_changes, memory_changes
│   └─► Generate JSON report
│
└─► Make Rollback Decision (Update Pipeline only)
    ├─► IF critical_failed > 0 → ROLLBACK
    ├─► IF failure_percentage > 30% → ROLLBACK
    ├─► IF avg_response_time_increase > 50% → ROLLBACK
    ├─► IF memory_increase > 100% → ROLLBACK
    └─► ELSE → SUCCESS
```

#### Test Output Format

Each test script outputs JSON to stdout:

```json
{
  "test_id": "INF-001",
  "name": "n8n Container Running State",
  "status": "pass|fail|skip",
  "priority": "P0|P1|P2",
  "criticality": "CRITICAL|HIGH|MEDIUM",
  "duration_ms": 1234,
  "timestamp": "2025-01-15T10:30:00Z",
  "error": "error message if failed",
  "details": {
    "container_status": "running",
    "health_status": "healthy"
  }
}
```

The runner collects all JSON outputs and aggregates them into a final report.

### 2. GitHub Actions Workflows

#### Update Pipeline Workflow



```yaml
name: n8n Update Pipeline

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:
    inputs:
      action:
        description: 'Action to perform'
        required: false
        default: 'update'
        type: choice
        options:
          - check
          - update
          - test
          - rollback
          - deploy-workflows
      target_version:
        description: 'Target n8n version (optional, for manual update)'
        required: false
        type: string
      rollback_id:
        description: 'Rollback point ID (optional, for manual rollback)'
        required: false
        type: string

jobs:
  update:
    runs-on: self-hosted
    timeout-minutes: 30
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Load configuration
        run: |
          # Parse config.yaml and export as environment variables
          # Set N8N_URL, CONTAINER_NAME, etc.
      
      - name: Detect new version
        id: detect
        run: |
          # Query Docker Hub API for latest n8n version
          # Compare against running version
          # Output: has_update=true/false, new_version=X.Y.Z
      
      - name: Create rollback point
        if: steps.detect.outputs.has_update == 'true'
        run: |
          ./scripts/backup.sh
          # Creates: image tag, DB dump, volume tarball
          # Outputs: rollback_id, backup_manifest.json
      
      - name: Run pre-update tests (baseline)
        if: steps.detect.outputs.has_update == 'true'
        run: |
          ./tests/runner.sh --mode=update --phase=pre-update
          # Saves: baseline.json with all metrics
      
      - name: Apply update
        if: steps.detect.outputs.has_update == 'true'
        run: |
          ./scripts/update.sh ${{ steps.detect.outputs.new_version }}
          # Pulls image, stops old container, starts new, waits for health
      
      - name: Run post-update tests
        if: steps.detect.outputs.has_update == 'true'
        run: |
          ./tests/runner.sh --mode=update --phase=post-update
          # Compares against baseline.json
          # Outputs: test_report.json, rollback_decision
      
      - name: Evaluate rollback decision
        id: rollback_decision
        if: steps.detect.outputs.has_update == 'true'
        run: |
          # Parse test_report.json
          # Check rollback criteria
          # Output: needs_rollback=true/false, reason="..."
      
      - name: Execute rollback
        if: steps.rollback_decision.outputs.needs_rollback == 'true'
        run: |
          ./scripts/rollback.sh ${{ steps.backup.outputs.rollback_id }}
          # Restores image, DB, volume
          # Runs health check subset to verify
      
      - name: Send notification
        if: always()
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: ${{ secrets.SMTP_HOST }}
          server_port: 587
          username: ${{ secrets.SMTP_USER }}
          password: ${{ secrets.SMTP_PASSWORD }}
          subject: |
            n8n Update: ${{ steps.rollback_decision.outputs.needs_rollback == 'true' && 'ROLLED BACK' || 'SUCCESS' }}
          body: |
            # Include test report summary
            # Include rollback reason if applicable
          to: ${{ secrets.NOTIFICATION_RECIPIENTS }}
      
      - name: Upload test report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-report-${{ github.run_id }}
          path: |
            tests/results/test_report.json
            tests/results/baseline.json
            tests/results/comparison.html
          retention-days: 90
```

#### Code Change Pipeline Workflow

```yaml
name: n8n Code Change Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  test:
    runs-on: self-hosted
    timeout-minutes: 15
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Validate test workflow JSON files
        if: contains(github.event.head_commit.modified, 'test-workflows/')
        run: |
          # For each modified JSON file in test-workflows/
          # Validate JSON syntax
          # Verify required fields (name, nodes, connections)
          # Verify node structure
      
      - name: Run code change tests
        run: |
          ./tests/runner.sh --mode=code-change
          # Runs: INF, NET, WEB, AUTH, DB, API, WF, CRED, SEC-001/002
          # Skips: PERF, BKP, NOTIF, ENV
      
      - name: Generate test summary
        if: always()
        run: |
          # Parse test_report.json
          # Generate markdown summary
          # Save to test_summary.md
      
      - name: Post PR comment
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const summary = fs.readFileSync('test_summary.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: summary
            });
      
      - name: Set commit status
        if: always()
        run: |
          # Use GitHub API to set commit status
          # Status: success/failure based on test results
      
      - name: Upload test report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: code-change-report-${{ github.run_id }}
          path: tests/results/test_report.json
          retention-days: 30
```

#### Health Check Pipeline Workflow

```yaml
name: n8n Daily Health Check

on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8 AM UTC
  workflow_dispatch:

jobs:
  health-check:
    runs-on: self-hosted
    timeout-minutes: 10
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Run health check tests
        run: |
          ./tests/runner.sh --mode=health-check
          # Runs: INF (all), NET (all), WEB (all), 
          #       DB-001/003/006, WF-001/002/008, SEC-001/002
      
      - name: Generate health report
        if: always()
        run: |
          # Parse test_report.json
          # Generate health summary
          # Determine: all_ok=true/false
      
      - name: Send health notification
        if: always()
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: ${{ secrets.SMTP_HOST }}
          server_port: 587
          username: ${{ secrets.SMTP_USER }}
          password: ${{ secrets.SMTP_PASSWORD }}
          subject: |
            n8n Health Check: ${{ steps.health.outputs.all_ok == 'true' && 'All OK' || 'ALERT - Failures Detected' }}
          body: |
            # Include health summary
            # List any failed tests
          to: ${{ secrets.NOTIFICATION_RECIPIENTS }}
      
      - name: Upload health report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: health-check-${{ github.run_id }}
          path: tests/results/test_report.json
          retention-days: 30
```

### 3. Backup and Rollback Mechanism

#### Backup Script (backup.sh)



```bash
#!/bin/bash
# backup.sh - Create a rollback point

set -e

ROLLBACK_ID=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/backups/n8n"
CONTAINER_NAME="n8n-production"
POSTGRES_CONTAINER="n8n-postgres"
DB_NAME="n8n"
DB_USER="n8n"

echo "Creating rollback point: $ROLLBACK_ID"

# 1. Tag current Docker image
CURRENT_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER_NAME)
docker tag $CURRENT_IMAGE "n8n-backup:$ROLLBACK_ID"

# 2. Dump PostgreSQL database
docker exec $POSTGRES_CONTAINER pg_dump -U $DB_USER $DB_NAME | \
  gzip > "$BACKUP_DIR/n8n_db_$ROLLBACK_ID.sql.gz"

# 3. Backup n8n data volume
VOLUME_NAME=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}' $CONTAINER_NAME)
docker run --rm -v $VOLUME_NAME:/data -v $BACKUP_DIR:/backup alpine \
  tar czf /backup/n8n_data_$ROLLBACK_ID.tar.gz -C /data .

# 4. Verify backups
test -f "$BACKUP_DIR/n8n_db_$ROLLBACK_ID.sql.gz" || exit 1
test -f "$BACKUP_DIR/n8n_data_$ROLLBACK_ID.tar.gz" || exit 1
gzip -t "$BACKUP_DIR/n8n_db_$ROLLBACK_ID.sql.gz" || exit 1

# 5. Calculate checksums
sha256sum "$BACKUP_DIR/n8n_db_$ROLLBACK_ID.sql.gz" > "$BACKUP_DIR/n8n_db_$ROLLBACK_ID.sql.gz.sha256"
sha256sum "$BACKUP_DIR/n8n_data_$ROLLBACK_ID.tar.gz" > "$BACKUP_DIR/n8n_data_$ROLLBACK_ID.tar.gz.sha256"

# 6. Create manifest
cat > "$BACKUP_DIR/manifest_$ROLLBACK_ID.json" <<EOF
{
  "rollback_id": "$ROLLBACK_ID",
  "timestamp": "$(date -Iseconds)",
  "n8n_version": "$(docker exec $CONTAINER_NAME n8n --version)",
  "image": "$CURRENT_IMAGE",
  "backup_tag": "n8n-backup:$ROLLBACK_ID",
  "database_backup": "n8n_db_$ROLLBACK_ID.sql.gz",
  "volume_backup": "n8n_data_$ROLLBACK_ID.tar.gz"
}
EOF

echo "Rollback point created: $ROLLBACK_ID"
echo "::set-output name=rollback_id::$ROLLBACK_ID"
```

#### Rollback Script (rollback.sh)

```bash
#!/bin/bash
# rollback.sh - Restore from a rollback point

set -e

ROLLBACK_ID=$1
BACKUP_DIR="/backups/n8n"
CONTAINER_NAME="n8n-production"
POSTGRES_CONTAINER="n8n-postgres"
DB_NAME="n8n"
DB_USER="n8n"

echo "Rolling back to: $ROLLBACK_ID"

# 1. Load manifest
MANIFEST="$BACKUP_DIR/manifest_$ROLLBACK_ID.json"
test -f "$MANIFEST" || { echo "Manifest not found"; exit 1; }

BACKUP_TAG=$(jq -r '.backup_tag' $MANIFEST)
DB_BACKUP=$(jq -r '.database_backup' $MANIFEST)
VOLUME_BACKUP=$(jq -r '.volume_backup' $MANIFEST)

# 2. Verify backups exist
test -f "$BACKUP_DIR/$DB_BACKUP" || exit 1
test -f "$BACKUP_DIR/$VOLUME_BACKUP" || exit 1

# 3. Stop current n8n container
docker stop $CONTAINER_NAME

# 4. Restore database
docker exec $POSTGRES_CONTAINER psql -U $DB_USER -c "DROP DATABASE IF EXISTS ${DB_NAME}_temp;"
docker exec $POSTGRES_CONTAINER psql -U $DB_USER -c "CREATE DATABASE ${DB_NAME}_temp;"
zcat "$BACKUP_DIR/$DB_BACKUP" | docker exec -i $POSTGRES_CONTAINER psql -U $DB_USER ${DB_NAME}_temp
docker exec $POSTGRES_CONTAINER psql -U $DB_USER -c "DROP DATABASE $DB_NAME;"
docker exec $POSTGRES_CONTAINER psql -U $DB_USER -c "ALTER DATABASE ${DB_NAME}_temp RENAME TO $DB_NAME;"

# 5. Restore data volume
VOLUME_NAME=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}' $CONTAINER_NAME)
docker run --rm -v $VOLUME_NAME:/data -v $BACKUP_DIR:/backup alpine sh -c \
  "rm -rf /data/* && tar xzf /backup/$VOLUME_BACKUP -C /data"

# 6. Start container with backup image
docker rm $CONTAINER_NAME
docker run -d --name $CONTAINER_NAME \
  --network n8n-network \
  -p 5678:5678 \
  -v $VOLUME_NAME:/home/node/.n8n \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=$POSTGRES_CONTAINER \
  -e DB_POSTGRESDB_DATABASE=$DB_NAME \
  -e DB_POSTGRESDB_USER=$DB_USER \
  -e DB_POSTGRESDB_PASSWORD=$DB_PASSWORD \
  $BACKUP_TAG

# 7. Wait for health
for i in {1..24}; do
  if curl -sf http://localhost:5678/healthz > /dev/null; then
    echo "n8n is healthy after rollback"
    exit 0
  fi
  echo "Waiting for n8n... ($i/24)"
  sleep 5
done

echo "ERROR: n8n did not become healthy after rollback"
exit 1
```

### 4. Data Models

#### Test Report JSON Schema

```json
{
  "pipeline": "update|code-change|health-check",
  "timestamp": "2025-01-15T10:30:00Z",
  "n8n_version_before": "1.71.0",
  "n8n_version_after": "1.72.0",
  "duration_seconds": 450,
  "summary": {
    "total": 65,
    "passed": 63,
    "failed": 2,
    "skipped": 0,
    "critical_failed": 0,
    "failure_percentage": 3.08
  },
  "tests": [
    {
      "test_id": "INF-001",
      "name": "n8n Container Running State",
      "status": "pass",
      "priority": "P0",
      "criticality": "CRITICAL",
      "duration_ms": 1234,
      "timestamp": "2025-01-15T10:30:00Z",
      "error": null,
      "details": {}
    }
  ],
  "baseline_comparison": {
    "response_times": {
      "avg_change_percent": 5.2,
      "endpoints": {
        "/api/v1/workflows": {
          "before_avg_ms": 120,
          "after_avg_ms": 126,
          "change_percent": 5.0
        }
      }
    },
    "memory_usage": {
      "before_mb": 512,
      "after_mb": 530,
      "change_percent": 3.5
    },
    "workflow_count": {
      "before": 42,
      "after": 42,
      "change": 0
    }
  },
  "rollback_decision": {
    "needs_rollback": false,
    "reason": null,
    "triggered_by": []
  }
}
```

#### Baseline JSON Schema

```json
{
  "timestamp": "2025-01-15T10:00:00Z",
  "n8n_version": "1.71.0",
  "container_uptime_seconds": 86400,
  "memory_usage_mb": 512,
  "workflow_count": 42,
  "active_workflow_count": 15,
  "credential_count": 8,
  "recent_execution_count": 1234,
  "response_times": {
    "/api/v1/workflows": {
      "min_ms": 100,
      "avg_ms": 120,
      "max_ms": 200,
      "p95_ms": 180
    },
    "/api/v1/executions": {
      "min_ms": 150,
      "avg_ms": 180,
      "max_ms": 300,
      "p95_ms": 250
    },
    "/webhook/health-check": {
      "min_ms": 50,
      "avg_ms": 80,
      "max_ms": 150,
      "p95_ms": 120
    }
  }
}
```

### 5. Error Handling

#### Test Failure Handling

- **CRITICAL test fails**: Stop all remaining tests, exit immediately
- **HIGH test fails**: Continue with remaining tests, contribute to rollback decision
- **MEDIUM test fails**: Continue with remaining tests, log only

#### Script Error Handling

- All scripts use `set -e` to exit on error
- Critical operations wrapped in error handlers
- Cleanup operations in `trap` handlers
- Rollback script has its own health verification

#### Rollback Failure Handling

If rollback itself fails:
1. Send CRITICAL alert email
2. Log detailed error information
3. Preserve failed state for manual investigation
4. Do NOT attempt automatic recovery
5. Require manual intervention

### 6. Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

#### Property 1: Container Health Preservation
*For any* n8n update, after the update completes (successfully or via rollback), the n8n container must be in a running and healthy state.
**Validates: Requirements UP-4, UP-7**

#### Property 2: Data Integrity Preservation
*For any* n8n update, the count of workflows, credentials, and executions must not decrease (data loss is never acceptable).
**Validates: Requirements UP-2, UP-7, DB-001, DB-003**

#### Property 3: Rollback Idempotence
*For any* rollback point, executing rollback twice should result in the same state as executing it once.
**Validates: Requirement UP-7**

#### Property 4: Backup Completeness
*For any* rollback point created, all three backup artifacts (image tag, database dump, volume tarball) must exist and be valid before the update proceeds.
**Validates: Requirement UP-2, BKP-001**

#### Property 5: Test Determinism
*For any* test in the test suite, running it twice against the same n8n state should produce the same pass/fail result.
**Validates: All test requirements**

#### Property 6: Critical Test Enforcement
*For any* test marked as CRITICAL (P0), if it fails, no further tests should execute and the pipeline should exit immediately.
**Validates: Requirements UP-5, UP-6**

#### Property 7: Rollback Trigger Consistency
*For any* post-update test run, if any rollback trigger condition is met (critical failure, >30% failure, >50% response time increase, >100% memory increase), rollback must be initiated.
**Validates: Requirement UP-6**

#### Property 8: Notification Delivery
*For any* pipeline execution that completes (success or failure), an email notification must be sent to all configured recipients.
**Validates: Requirement NR-1**

#### Property 9: Baseline Comparison Validity
*For any* post-update test run, all metrics compared against baseline must have corresponding baseline values (no comparison against missing data).
**Validates: Requirement UP-3, UP-5**

#### Property 10: Credential Decryption Preservation
*For any* n8n update, if credentials were decryptable before the update, they must remain decryptable after the update (encryption key must be preserved).
**Validates: Requirement CRED-001**

### 7. Testing Strategy

#### Unit Testing
- Test individual bash functions in isolation
- Mock Docker commands for testing
- Verify JSON parsing and generation
- Test rollback decision logic

#### Integration Testing
- Test full pipeline execution in test environment
- Verify backup/restore cycle
- Test notification delivery
- Verify GitHub Actions workflow syntax

#### Property-Based Testing
- Generate random test results and verify rollback decision logic
- Generate random baseline data and verify comparison logic
- Test with various failure scenarios

### 8. Error Handling

All scripts follow these error handling principles:

```bash
#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Cleanup on exit
trap cleanup EXIT

cleanup() {
  # Remove temporary files
  # Restore state if needed
}

# Error handler
error_handler() {
  echo "ERROR: $1" >&2
  # Log error
  # Send alert if critical
  exit 1
}
```

## Implementation Notes

### Authentication Note
**IMPORTANT**: Basic HTTP authentication is deprecated in newer n8n versions (1.0+). The test workflows and CRED-001 test should use API key authentication or OAuth instead of basic auth. The credential test workflow should be updated to use a test API endpoint that requires authentication via API key header.

### Performance Considerations
- Tests run sequentially within phases to avoid resource contention
- Parallel execution only where safe (AUTH + DB phase)
- Test timeout: 10 seconds per test, 30 minutes total pipeline
- Backup operations use compression to save disk space

### Security Considerations
- All secrets stored in GitHub Actions encrypted secrets
- Never log sensitive values (passwords, API keys, encryption keys)
- Backup files should be encrypted at rest
- Test API key has minimum required permissions

### Scalability Considerations
- Multi-instance support via configuration
- Each instance has independent state and baselines
- Parallel pipeline execution for multiple instances
- Shared test scripts, instance-specific configuration

