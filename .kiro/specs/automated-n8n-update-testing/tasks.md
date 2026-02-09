# Implementation Plan: Automated n8n Update and Testing System

## Overview

This implementation plan is split into two phases:
- **Phase 1: Mini Demo/MVP** - Working pipeline with essential tests (~10 tests) to prove the concept
- **Phase 2: Full Implementation** - Complete all 65 tests and advanced features

This allows you to get a working system quickly, validate the approach, and then expand to full coverage.

---

# Phase 1: Mini Demo/MVP (1-2 weeks)

Goal: Get a working Update Pipeline with basic health checks, backup/rollback, and notifications.

## Phase 1 Tasks

## Phase 1 Tasks

- [x] 1. Project Setup
  - Create directory structure: tests/, scripts/, test-workflows/, .github/workflows/
  - Create basic config.yaml with n8n URL, container names, thresholds
  - Set up GitHub Actions secrets (N8N_TEST_API_KEY, SMTP credentials)
  - _Requirements: 15_

- [x] 2. Simple Test Runner (MVP version)
  - [x] 2.1 Create tests/runner.sh script
    - Accept --mode parameter (update, health-check)
    - Load config from config.yaml
    - Execute tests sequentially
    - Output simple pass/fail summary
    - Exit with code 0 (success) or 1 (failure)
    - _Requirements: UP-3, UP-5_

  - [x] 2.2 Create test output format
    - Each test outputs: TEST_ID STATUS MESSAGE
    - Runner collects and counts pass/fail
    - Generate simple JSON report
    - _Requirements: NR-2_

- [x] 3. Essential Tests (10 tests only)
  - [x] 3.1 INF-001: n8n Container Running
    - Check `docker ps` shows n8n container
    - Verify status is "Up"
    - _Requirements: 8_

  - [x] 3.2 INF-003: PostgreSQL Health
    - Run `docker exec postgres pg_isready`
    - Verify exit code 0
    - _Requirements: 8_

  - [x] 3.3 NET-001: HTTP Port Accessible
    - curl n8n URL
    - Verify HTTP 200
    - _Requirements: 9_

  - [x] 3.4 WEB-003: Healthcheck Endpoint
    - GET /healthz
    - Verify healthy response
    - _Requirements: 9_

  - [x] 3.5 DB-001: Database Query
    - Count workflows in database
    - Verify query succeeds
    - _Requirements: 10_

  - [x] 3.6 API-001: List Workflows
    - GET /api/v1/workflows with API key
    - Verify HTTP 200 and valid JSON
    - _Requirements: 11_

  - [x] 3.7 WF-001: Basic Webhook Test
    - POST to test webhook
    - Verify response
    - _Requirements: 11_

  - [x] 3.8 CRED-001: Credential Decryption (CRITICAL)
    - Trigger credential test workflow
    - Verify no decryption errors
    - _Requirements: 11_

  - [x] 3.9 PERF-001: Response Time Check
    - Measure API response time
    - Compare against baseline (if exists)
    - _Requirements: 11_

  - [x] 3.10 BKP-001: Backup Verification
    - Verify backup files exist
    - Check they are non-empty
    - _Requirements: 11_

- [x] 4. Test Workflows (2 workflows only)
  - [x] 4.1 Create health-check.json
    - Webhook trigger on /health-check
    - Simple response with status:ok
    - _Requirements: 11, WF-001_

  - [x] 4.2 Create credential-test.json
    - Webhook trigger on /test-credential
    - HTTP Request with test credential
    - Return success/failure
    - _Requirements: 11, CRED-001_

  - [x] 4.3 Create deploy-test-workflows.sh
    - Import 2 test workflows via API
    - Activate them
    - _Requirements: 11_
    - _Note: Using existing import-test-workflows.sh_

- [x] 5. Backup and Rollback Scripts (Simple version)
  - [x] 5.1 Create backup.sh
    - Tag current Docker image
    - Dump PostgreSQL database
    - Create manifest file
    - _Requirements: UP-2_

  - [x] 5.2 Create rollback.sh
    - Load manifest
    - Restore Docker image
    - Restore database
    - Restart container
    - _Requirements: UP-7_

  - [x] 5.3 Create update.sh
    - Pull new image
    - Stop old container
    - Start new container
    - Wait for health
    - _Requirements: UP-4_

- [x] 6. Update Pipeline (GitHub Actions)
  - [x] 6.1 Create .github/workflows/update-pipeline.yml
    - Manual trigger only (no schedule yet)
    - Input: target_version
    - Steps:
      1. Checkout code
      2. Create backup (run backup.sh)
      3. Run pre-update tests (runner.sh)
      4. Save baseline
      5. Apply update (run update.sh)
      6. Run post-update tests (runner.sh)
      7. Compare results
      8. Decide: rollback or success
      9. Execute rollback if needed (run rollback.sh)
      10. Send email notification
      11. Upload test report
    - _Requirements: UP-1 through UP-7_

  - [x] 6.2 Add email notification step
    - Use dawidd6/action-send-mail
    - Send on success or failure
    - Include test summary
    - _Requirements: NR-1_

- [x] 7. Health Check Pipeline (GitHub Actions)
  - [x] 7.1 Create .github/workflows/health-check-pipeline.yml
    - Manual trigger only (no schedule yet)
    - Run subset of tests (INF, NET, WEB, DB, API, WF)
    - Send email summary
    - _Requirements: HC-1_

- [ ] 8. Testing and Validation
  - [ ] 8.1 Test backup/rollback locally
    - Create backup
    - Verify files exist
    - Test rollback
    - Verify restoration works
    - _Requirements: UP-2, UP-7_

  - [ ] 8.2 Test Update Pipeline manually
    - Trigger workflow with current version
    - Verify all steps execute
    - Check email notification received
    - _Requirements: UP-1 through UP-7_

  - [ ] 8.3 Test Health Check Pipeline
    - Trigger workflow manually
    - Verify tests run
    - Check email received
    - _Requirements: HC-1_

- [x] 9. Documentation
  - [x] 9.1 Create MVP README
    - Setup instructions
    - How to deploy test workflows
    - How to trigger pipelines
    - How to read test results
    - _Requirements: All_
    - _Created: docs/PHASE1-COMPLETE.md_

- [ ] 10. Demo Checkpoint
  - Verify you can:
    - [ ] Manually trigger Update Pipeline
    - [ ] See 10 tests execute
    - [ ] Backup is created
    - [ ] Update is applied (or simulated)
    - [ ] Tests run post-update
    - [ ] Email notification received
    - [ ] Rollback works if triggered
  - **Decision point: Proceed to Phase 2 or iterate on MVP?**

---

# Phase 2: Full Implementation (3-4 weeks)

Goal: Complete all 65 tests, add Code Change Pipeline, add scheduling, add all advanced features.

## Phase 2 Tasks

## Phase 2 Tasks

- [ ] 11. Enhance Test Runner
  - [ ] 11.1 Add test phases (1-10)
    - Implement sequential phase execution
    - Stop on CRITICAL failures
    - Support parallel execution where safe
    - _Requirements: UP-5_

  - [ ] 11.2 Add baseline comparison
    - Load pre-update baseline
    - Compare all metrics
    - Calculate percentage changes
    - _Requirements: UP-3, UP-5_

  - [ ] 11.3 Add rollback decision logic
    - Check all rollback triggers
    - Generate decision with reason
    - _Requirements: UP-6_

- [ ] 12. Complete Infrastructure Tests (INF)
  - [ ] 12.1 INF-002: Container Uptime Stability
  - [ ] 12.2 INF-004: Docker Network Connectivity
  - [ ] 12.3 INF-005: Docker Volume Mounts
  - [ ] 12.4 INF-006: Container Resource Usage
  - _Requirements: 8_

- [ ] 13. Complete Network & Web Tests (NET, WEB)
  - [ ] 13.1 NET-002: Webhook Endpoint Reachability
  - [ ] 13.2 NET-003: External Network Connectivity
  - [ ] 13.3 NET-004: Reverse Proxy Health
  - [ ] 13.4 WEB-001: Editor Page Load
  - [ ] 13.5 WEB-002: Static Assets Serving
  - [ ] 13.6 WEB-004: Version Verification
  - [ ] 13.7 WEB-005: WebSocket Connection
  - _Requirements: 9_

- [ ] 14. Complete Authentication Tests (AUTH)
  - [ ] 14.1 AUTH-001: API Key Authentication
  - [ ] 14.2 AUTH-002: User Login
  - [ ] 14.3 AUTH-003: RBAC Permission Enforcement
  - [ ] 14.4 AUTH-004: Unauthenticated Access Prevention
  - [ ] 14.5 AUTH-005: SSO Integration
  - _Requirements: 10_

- [ ] 15. Complete Database Tests (DB)
  - [ ] 15.1 DB-002: Schema Migration Verification
  - [ ] 15.2 DB-003: Workflow Data Integrity
  - [ ] 15.3 DB-004: Credential Encryption Verification
  - [ ] 15.4 DB-005: Query Performance
  - [ ] 15.5 DB-006: Connection Pool Health
  - _Requirements: 10_

- [ ] 16. Complete API Tests (API)
  - [ ] 16.1 API-002: Workflow CRUD Cycle
  - [ ] 16.2 API-003: Workflow Activation/Deactivation
  - [ ] 16.3 API-004: Execution History
  - [ ] 16.4 API-005: Credentials API
  - [ ] 16.5 API-006: Error Handling and Rate Limiting
  - _Requirements: 11_

- [ ] 17. Complete Workflow Tests (WF)
  - [ ] 17.1 WF-002: Data Transformation
  - [ ] 17.2 WF-003: HTTP Request Node
  - [ ] 17.3 WF-004: Error Handling
  - [ ] 17.4 WF-005: Scheduled Trigger Verification
  - [ ] 17.5 WF-006: Sub-Workflow Execution
  - [ ] 17.6 WF-007: Parallel Execution
  - [ ] 17.7 WF-008: Production Workflow Smoke Test
  - _Requirements: 11_

- [ ] 18. Complete Credential Tests (CRED)
  - [ ] 18.1 CRED-002: Credential Count Consistency
  - [ ] 18.2 CRED-003: Environment Variables Integrity
  - [ ] 18.3 CRED-004: Credential Sharing
  - _Requirements: 11_

- [ ] 19. Complete Performance Tests (PERF)
  - [ ] 19.1 PERF-002: Workflow Execution Time Benchmark
  - [ ] 19.2 PERF-003: Memory Usage Under Load
  - [ ] 19.3 PERF-004: Database Connection Stress
  - [ ] 19.4 PERF-005: Large Payload Processing
  - _Requirements: 11_

- [ ] 20. Complete Backup Tests (BKP)
  - [ ] 20.1 BKP-002: Database Backup Restorability
  - [ ] 20.2 BKP-003: Docker Image Rollback Capability
  - [ ] 20.3 BKP-004: Backup Retention
  - _Requirements: 11_

- [ ] 21. Complete Security Tests (SEC)
  - [ ] 21.1 SEC-001: TLS Configuration
  - [ ] 21.2 SEC-002: Security Headers
  - [ ] 21.3 SEC-003: CVE Vulnerability Scan
  - [ ] 21.4 SEC-004: Node Package Integrity
  - [ ] 21.5 SEC-005: Container Security
  - [ ] 21.6 SEC-006: Execution Data Cleanup
  - _Requirements: 11_

- [ ] 22. Complete Notification Tests (NOTIF)
  - [ ] 22.1 NOTIF-001: Email Delivery
  - [ ] 22.2 NOTIF-002: Alert Channel Verification
  - [ ] 22.3 NOTIF-003: n8n Error Workflow
  - _Requirements: 12_

- [ ] 23. Complete Environment Tests (ENV)
  - [ ] 23.1 ENV-001: Instance Configuration Consistency
  - [ ] 23.2 ENV-002: Environment Parity
  - [ ] 23.3 ENV-003: Source Control Integration
  - _Requirements: 17_

- [ ] 24. Complete Test Workflows
  - [ ] 24.1 Create data-transform.json
  - [ ] 24.2 Create http-request.json
  - [ ] 24.3 Create error-handling.json
  - [ ] 24.4 Create cron-test.json
  - [ ] 24.5 Create parent-workflow.json and child-workflow.json
  - _Requirements: 11_

- [ ] 25. Enhance Backup/Rollback Scripts
  - [ ] 25.1 Add data volume backup to backup.sh
  - [ ] 25.2 Add data volume restore to rollback.sh
  - [ ] 25.3 Add checksum verification
  - [ ] 25.4 Add backup retention cleanup
  - _Requirements: UP-2, UP-7_

- [ ] 26. Code Change Pipeline
  - [ ] 26.1 Create .github/workflows/code-change-pipeline.yml
    - Trigger on push and PR
    - Validate test workflow JSON
    - Run code change test subset
    - Post PR comment with results
    - Set commit status
    - _Requirements: CC-1, CC-2_

- [ ] 27. Add Scheduling
  - [ ] 27.1 Add cron schedule to Update Pipeline (daily 2 AM)
  - [ ] 27.2 Add cron schedule to Health Check Pipeline (daily 8 AM)
  - [ ] 27.3 Add automatic version detection to Update Pipeline
  - _Requirements: UP-1, HC-1_

- [ ] 28. Enhanced Configuration
  - [ ] 28.1 Expand config.yaml with all settings
    - All test configurations
    - All thresholds
    - Feature flags
    - Multi-instance support
    - _Requirements: 15_

  - [ ] 28.2 Add configuration validation
    - Verify all required fields present
    - Validate threshold values
    - Check feature flag combinations
    - _Requirements: 15_

- [ ] 29. Audit Logging
  - [ ] 29.1 Implement persistent audit log
    - Log all significant events
    - Store on host (not just GitHub logs)
    - Include timestamps, versions, decisions
    - _Requirements: 16_

  - [ ] 29.2 Add log query command
    - Filter by date, event type, version
    - Export to CSV or JSON
    - _Requirements: 16_

- [ ] 30. Complete Documentation
  - [ ] 30.1 Expand README with full setup guide
  - [ ] 30.2 Create ARCHITECTURE.md
  - [ ] 30.3 Create TROUBLESHOOTING.md
  - [ ] 30.4 Document all 65 tests
  - _Requirements: All_

- [ ] 31. Full Integration Testing
  - [ ] 31.1 Test all 65 tests execute correctly
  - [ ] 31.2 Test all rollback scenarios
  - [ ] 31.3 Test Code Change Pipeline
  - [ ] 31.4 Test scheduled execution
  - [ ] 31.5 Test multi-instance support
  - _Requirements: All_

- [ ] 32. Production Deployment
  - [ ] 32.1 Deploy all test workflows to production
  - [ ] 32.2 Enable all GitHub Actions workflows
  - [ ] 32.3 Monitor first week of executions
  - [ ] 32.4 Tune thresholds based on real data
  - _Requirements: All_

---

## Notes

- **Phase 1 is the MVP** - Get this working first before expanding
- **Phase 1 should take 1-2 weeks** - Focus on core functionality
- **Phase 2 adds completeness** - All 65 tests and advanced features
- **Phase 2 should take 3-4 weeks** - Can be done incrementally
- Each task references specific requirements for traceability
- Test early and often - don't wait until everything is built
  - [ ] 2.1 Implement main test runner script (tests/runner.sh)
    - Parse command-line arguments (--mode, --phase)
    - Load configuration from config.yaml
    - Initialize state management (baselines, counters)
    - Implement test execution phases (1-10)
    - Handle CRITICAL test failures (stop execution)
    - Aggregate test results into JSON report
    - _Requirements: UP-3, UP-5_

  - [ ] 2.2 Implement test output format and JSON generation
    - Define JSON schema for individual test results
    - Implement JSON aggregation for final report
    - Generate comparison reports (pre vs post update)
    - _Requirements: NR-2_

  - [ ] 2.3 Implement state management
    - Save and load baseline data (baseline.json)
    - Track test execution history
    - Store rollback point metadata
    - _Requirements: UP-3_

- [ ] 3. Infrastructure Tests (INF Category)
  - [ ] 3.1 Implement INF-001: n8n Container Running State
    - Check container status via `docker inspect`
    - Verify health status if healthcheck defined
    - Capture logs on failure
    - _Requirements: 8_

  - [ ] 3.2 Implement INF-002: Container Uptime Stability
    - Get container start time and uptime
    - Check restart count
    - Compare against previous state
    - _Requirements: 8_

  - [ ] 3.3 Implement INF-003: PostgreSQL Container Health
    - Check PostgreSQL container status
    - Run `pg_isready` command
    - Verify "accepting connections"
    - _Requirements: 8_

  - [ ] 3.4 Implement INF-004: Docker Network Connectivity
    - Test n8n to PostgreSQL connectivity
    - Verify Docker network exists
    - _Requirements: 8_

  - [ ] 3.5 Implement INF-005: Docker Volume Mounts
    - Parse and verify volume mounts
    - Test write access to volumes
    - _Requirements: 8_

  - [ ] 3.6 Implement INF-006: Container Resource Usage
    - Parse `docker stats` output
    - Compare against thresholds and baseline
    - _Requirements: 8_

- [ ] 4. Network & Web Tests (NET, WEB Categories)
  - [ ] 4.1 Implement NET-001: HTTP Port Accessibility
    - Send HTTP GET to n8n URL
    - Verify response code and time
    - Check TLS certificate if HTTPS
    - _Requirements: 9_

  - [ ] 4.2 Implement NET-002: Webhook Endpoint Reachability
    - POST to test webhook endpoint
    - Verify response and timing
    - _Requirements: 9_

  - [ ] 4.3 Implement NET-003: External Network Connectivity
    - Make outbound HTTPS request from container
    - Verify proxy settings if applicable
    - _Requirements: 9_

  - [ ] 4.4 Implement NET-004: Reverse Proxy Health
    - Test through public URL
    - Verify WebSocket upgrade support
    - Check TLS termination
    - _Requirements: 9_

  - [ ] 4.5 Implement WEB-001: Editor Page Load
    - GET n8n base URL
    - Verify HTML content and markers
    - Check response time
    - _Requirements: 9_

  - [ ] 4.6 Implement WEB-002: Static Assets Serving
    - Parse HTML for asset URLs
    - Verify first 5 assets load correctly
    - _Requirements: 9_

  - [ ] 4.7 Implement WEB-003: REST API Healthcheck
    - GET /healthz endpoint
    - Verify healthy status
    - _Requirements: 9_

  - [ ] 4.8 Implement WEB-004: Version Verification
    - Query n8n version via API or Docker
    - Compare against expected version
    - _Requirements: 9_

  - [ ] 4.9 Implement WEB-005: WebSocket Connection
    - Open WebSocket to /rest/push
    - Verify handshake and connection stability
    - _Requirements: 9_

- [ ] 5. Authentication & Database Tests (AUTH, DB Categories)
  - [ ] 5.1 Implement AUTH-001: API Key Authentication
    - Test valid API key (positive)
    - Test invalid API key (negative)
    - _Requirements: 10_

  - [ ] 5.2 Implement AUTH-002: User Login
    - Test valid credentials
    - Test invalid credentials
    - Verify rate limiting
    - _Requirements: 10_

  - [ ] 5.3 Implement AUTH-003: RBAC Permission Enforcement
    - Test viewer role permissions
    - Test editor role permissions
    - Test admin permissions
    - _Requirements: 10_

  - [ ] 5.4 Implement AUTH-004: Unauthenticated Access Prevention
    - Test all protected endpoints without auth
    - Verify 401 responses
    - Verify no data leakage
    - _Requirements: 10_

  - [ ] 5.5 Implement AUTH-005: SSO Integration
    - Verify SSO metadata/connection
    - Skip if SSO not configured
    - _Requirements: 10_

  - [ ] 5.6 Implement DB-001: Database Connection and Query
    - Execute count queries on key tables
    - Compare against baseline
    - Detect data loss
    - _Requirements: 10_

  - [ ] 5.7 Implement DB-002: Schema Migration Verification
    - Query migrations table
    - List and verify all tables
    - Check key columns exist
    - _Requirements: 10_

  - [ ] 5.8 Implement DB-003: Workflow Data Integrity
    - Query sample workflows
    - Parse and validate nodes JSON
    - Verify no NULL nodes
    - _Requirements: 10_

  - [ ] 5.9 Implement DB-004: Credential Encryption Verification
    - Query credentials
    - Verify data is encrypted
    - Check for plaintext patterns
    - _Requirements: 10_

  - [ ] 5.10 Implement DB-005: Query Performance
    - Run EXPLAIN ANALYZE on key queries
    - Compare against baseline
    - Verify indexes exist
    - _Requirements: 10_

  - [ ] 5.11 Implement DB-006: Connection Pool Health
    - Query pg_stat_activity
    - Check connection counts
    - Detect connection leaks
    - _Requirements: 10_

- [ ] 6. API & Workflow Tests (API, WF Categories)
  - [ ] 6.1 Implement API-001: List Workflows
    - GET /api/v1/workflows
    - Verify response structure
    - Test filtering and pagination
    - _Requirements: 11_

  - [ ] 6.2 Implement API-002: Workflow CRUD Cycle
    - Create test workflow
    - Read, update, delete
    - Verify cleanup
    - _Requirements: 11_

  - [ ] 6.3 Implement API-003: Workflow Activation/Deactivation
    - Create workflow with webhook trigger
    - Test activation and deactivation
    - _Requirements: 11_

  - [ ] 6.4 Implement API-004: Execution History
    - GET /api/v1/executions
    - Verify response structure
    - Test filtering and pagination
    - _Requirements: 11_

  - [ ] 6.5 Implement API-005: Credentials API
    - GET /api/v1/credentials
    - Verify no decrypted data exposed
    - Check credential types endpoint
    - _Requirements: 11_

  - [ ] 6.6 Implement API-006: Error Handling and Rate Limiting
    - Test 404, 400 responses
    - Test rate limiting if configured
    - _Requirements: 11_

  - [ ] 6.7 Implement WF-001: Basic Webhook Test
    - POST to /webhook/health-check
    - Verify response and timing
    - Check execution history
    - _Requirements: 11_

  - [ ] 6.8 Implement WF-002: Data Transformation
    - POST to /webhook/test-transform
    - Verify transformation logic
    - _Requirements: 11_

  - [ ] 6.9 Implement WF-003: HTTP Request Node
    - POST to /webhook/test-http
    - Verify outbound request succeeded
    - _Requirements: 11_

  - [ ] 6.10 Implement WF-004: Error Handling
    - Test success and error paths
    - Verify error handler works
    - _Requirements: 11_

  - [ ] 6.11 Implement WF-005: Scheduled Trigger Verification
    - Activate cron workflow
    - Wait and check execution history
    - Deactivate and cleanup
    - _Requirements: 11_

  - [ ] 6.12 Implement WF-006: Sub-Workflow Execution
    - POST to /webhook/test-subworkflow
    - Verify parent and child execution
    - _Requirements: 11_

  - [ ] 6.13 Implement WF-007: Parallel Execution
    - Send 10 parallel requests
    - Verify all succeed
    - _Requirements: 11_

  - [ ] 6.14 Implement WF-008: Production Workflow Smoke Test
    - List active workflows
    - Compare against baseline
    - Verify no unexpected deactivations
    - _Requirements: 11_

- [ ] 7. Credential Tests (CRED Category)
  - [ ] 7.1 Implement CRED-001: Credential Decryption (CRITICAL)
    - Trigger test credential workflow
    - Verify no decryption errors
    - _Requirements: 11_

  - [ ] 7.2 Implement CRED-002: Credential Count Consistency
    - GET credentials and count
    - Compare against baseline
    - _Requirements: 11_

  - [ ] 7.3 Implement CRED-003: Environment Variables Integrity
    - Check presence of key env vars
    - Never log sensitive values
    - _Requirements: 11_

  - [ ] 7.4 Implement CRED-004: Credential Sharing
    - Verify sharing permissions
    - Skip if Enterprise not enabled
    - _Requirements: 11_

- [ ] 8. Performance Tests (PERF Category)
  - [ ] 8.1 Implement PERF-001: API Response Time Benchmark
    - Execute 10 iterations of key endpoints
    - Calculate statistics
    - Compare against baseline
    - _Requirements: 11_

  - [ ] 8.2 Implement PERF-002: Workflow Execution Time Benchmark
    - Execute WF-002 10 times
    - Record internal and external times
    - Compare against baseline
    - _Requirements: 11_

  - [ ] 8.3 Implement PERF-003: Memory Usage Under Load
    - Record initial memory
    - Execute 50 requests
    - Check for memory leaks
    - _Requirements: 11_

  - [ ] 8.4 Implement PERF-004: Database Connection Stress
    - Send 20 parallel requests
    - Monitor pg_stat_activity
    - Verify no connection errors
    - _Requirements: 11_

  - [ ] 8.5 Implement PERF-005: Large Payload Processing
    - Send 1MB JSON payload
    - Verify processing succeeds
    - _Requirements: 11_

- [ ] 9. Backup & Security Tests (BKP, SEC Categories)
  - [ ] 9.1 Implement BKP-001: Backup Completeness (CRITICAL)
    - Verify all backup artifacts exist
    - Validate gzip and tarball
    - Count tables in DB dump
    - _Requirements: 11_

  - [ ] 9.2 Implement BKP-002: Database Backup Restorability
    - Create temp database
    - Restore backup
    - Verify workflow count
    - Cleanup
    - _Requirements: 11_

  - [ ] 9.3 Implement BKP-003: Docker Image Rollback Capability
    - Verify backup image exists
    - Test starting backup image
    - Cleanup
    - _Requirements: 11_

  - [ ] 9.4 Implement BKP-004: Backup Retention
    - List backup files
    - Verify retention policy
    - Check disk usage
    - _Requirements: 11_

  - [ ] 9.5 Implement SEC-001: TLS Configuration
    - Use openssl to verify TLS
    - Check certificate validity
    - Verify HSTS header
    - _Requirements: 11_

  - [ ] 9.6 Implement SEC-002: Security Headers
    - Verify all security headers present
    - Check cookie flags
    - _Requirements: 11_

  - [ ] 9.7 Implement SEC-003: CVE Vulnerability Scan
    - Scan Docker image with Trivy
    - Compare against pre-update scan
    - _Requirements: 11_

  - [ ] 9.8 Implement SEC-004: Node Package Integrity
    - List installed packages
    - Compare against expected count
    - _Requirements: 11_

  - [ ] 9.9 Implement SEC-005: Container Security
    - Verify container security settings
    - Check user, privileges, limits
    - _Requirements: 11_

  - [ ] 9.10 Implement SEC-006: Execution Data Cleanup
    - Verify pruning is enabled
    - Check execution age
    - _Requirements: 11_

- [ ] 10. Notification & Environment Tests (NOTIF, ENV Categories)
  - [ ] 10.1 Implement NOTIF-001: Email Delivery
    - Send test email via SMTP
    - Verify delivery if test mailbox available
    - _Requirements: 12_

  - [ ] 10.2 Implement NOTIF-002: Alert Channel Verification
    - Validate email addresses
    - Test Slack webhook if configured
    - _Requirements: 12_

  - [ ] 10.3 Implement NOTIF-003: n8n Error Workflow
    - Verify Error Workflow configured
    - Trigger test error
    - Verify error workflow executed
    - _Requirements: 12_

  - [ ] 10.4 Implement ENV-001: Instance Configuration Consistency
    - Check each configured instance
    - Generate comparison matrix
    - _Requirements: 17_

  - [ ] 10.5 Implement ENV-002: Environment Parity
    - Compare test vs production
    - Log all differences
    - _Requirements: 17_

  - [ ] 10.6 Implement ENV-003: Source Control Integration
    - Verify Git connection
    - Check branch and last pull
    - _Requirements: 17_

- [ ] 11. Backup and Rollback Scripts
  - [ ] 11.1 Implement backup.sh script
    - Tag Docker image
    - Dump PostgreSQL database
    - Backup data volume
    - Verify backups and calculate checksums
    - Create manifest JSON
    - _Requirements: UP-2_

  - [ ] 11.2 Implement rollback.sh script
    - Load manifest
    - Verify backups exist
    - Stop current container
    - Restore database
    - Restore data volume
    - Start container with backup image
    - Wait for health
    - _Requirements: UP-7_

  - [ ] 11.3 Implement update.sh script
    - Pull new Docker image
    - Stop old container
    - Start new container with same config
    - Wait for health with timeout
    - _Requirements: UP-4_

- [ ] 12. Test Workflows (n8n workflows for testing)
  - [ ] 12.1 Create health-check.json workflow
    - Webhook trigger on /health-check
    - Set node with status fields
    - Respond to webhook
    - _Requirements: 11, WF-001_

  - [ ] 12.2 Create data-transform.json workflow
    - Webhook trigger on /test-transform
    - Code node with transformation logic
    - Respond to webhook
    - _Requirements: 11, WF-002_

  - [ ] 12.3 Create http-request.json workflow
    - Webhook trigger on /test-http
    - HTTP Request node to external API
    - Set node with success flag
    - Respond to webhook
    - _Requirements: 11, WF-003_

  - [ ] 12.4 Create error-handling.json workflow
    - Webhook trigger on /test-error
    - Code node with conditional error
    - Error handler path
    - Success and error response nodes
    - _Requirements: 11, WF-004_

  - [ ] 12.5 Create cron-test.json workflow
    - Cron trigger (every minute)
    - Set node with timestamp
    - _Requirements: 11, WF-005_

  - [ ] 12.6 Create parent-workflow.json and child-workflow.json
    - Parent: webhook trigger, Execute Workflow node
    - Child: Execute Workflow Trigger, Code node
    - _Requirements: 11, WF-006_

  - [ ] 12.7 Create credential-test.json workflow
    - Webhook trigger on /test-credential
    - HTTP Request with test credential
    - Set node with success/failure flag
    - Respond to webhook
    - _Requirements: 11, CRED-001_

  - [ ] 12.8 Create deploy-test-workflows.sh script
    - Import all test workflows via API
    - Store workflow IDs in config
    - Activate workflows as needed
    - _Requirements: 11_

- [ ] 13. GitHub Actions Workflows
  - [ ] 13.1 Create update-pipeline.yml workflow
    - Schedule trigger (daily 2 AM)
    - Manual trigger with inputs
    - Detect new version step
    - Create rollback point step
    - Run pre-update tests step
    - Apply update step
    - Run post-update tests step
    - Evaluate rollback decision step
    - Execute rollback step (conditional)
    - Send notification step
    - Upload artifacts step
    - _Requirements: UP-1 through UP-7, NR-1, NR-2_

  - [ ] 13.2 Create code-change-pipeline.yml workflow
    - Push and PR triggers
    - Validate test workflow JSON step
    - Run code change tests step
    - Generate test summary step
    - Post PR comment step (conditional)
    - Set commit status step
    - Upload artifacts step
    - _Requirements: CC-1, CC-2, NR-2_

  - [ ] 13.3 Create health-check-pipeline.yml workflow
    - Schedule trigger (daily 8 AM)
    - Manual trigger
    - Run health check tests step
    - Generate health report step
    - Send health notification step
    - Upload artifacts step
    - _Requirements: HC-1, NR-1, NR-2_

- [ ] 14. Configuration and Documentation
  - [ ] 14.1 Create tests/config.yaml configuration file
    - n8n connection settings
    - PostgreSQL settings
    - Rollback thresholds
    - Backup settings
    - Notification settings
    - Feature flags
    - Test workflow definitions
    - _Requirements: 15_

  - [ ] 14.2 Create README.md with setup instructions
    - Prerequisites
    - Installation steps
    - Configuration guide
    - GitHub secrets setup
    - Test workflow deployment
    - Manual commands
    - Troubleshooting
    - _Requirements: All_

  - [ ] 14.3 Create ARCHITECTURE.md documentation
    - System architecture diagrams
    - Component descriptions
    - Data flow diagrams
    - Decision trees
    - _Requirements: All_

- [ ] 15. Testing and Validation
  - [ ] 15.1 Test backup and rollback scripts locally
    - Create test backup
    - Verify all artifacts
    - Perform test rollback
    - Verify restoration
    - _Requirements: UP-2, UP-7_

  - [ ] 15.2 Test individual test scripts
    - Run each test category script
    - Verify JSON output format
    - Test error handling
    - _Requirements: All test requirements_

  - [ ] 15.3 Test full pipeline execution
    - Run Update Pipeline in test environment
    - Verify all steps execute correctly
    - Test rollback trigger scenarios
    - Verify notifications sent
    - _Requirements: UP-1 through UP-7_

  - [ ] 15.4 Test Code Change Pipeline
    - Push test changes
    - Verify pipeline triggers
    - Check PR comments
    - Verify commit status
    - _Requirements: CC-1, CC-2_

  - [ ] 15.5 Test Health Check Pipeline
    - Trigger manually
    - Verify health checks run
    - Check notification delivery
    - _Requirements: HC-1_

- [ ] 16. Deployment and Go-Live
  - [ ] 16.1 Deploy test workflows to production n8n
    - Run deploy-test-workflows.sh
    - Verify all workflows imported
    - Activate workflows
    - Test webhooks manually
    - _Requirements: 11_

  - [ ] 16.2 Configure GitHub Actions secrets
    - Add N8N_TEST_API_KEY
    - Add N8N_DB_PASSWORD
    - Add SMTP credentials
    - Add notification recipients
    - _Requirements: 15_

  - [ ] 16.3 Enable GitHub Actions workflows
    - Commit all workflow files
    - Verify self-hosted runner is active
    - Test manual trigger
    - Monitor first scheduled run
    - _Requirements: UP-1, CC-1, HC-1_

  - [ ] 16.4 Monitor and iterate
    - Review first week of executions
    - Adjust thresholds if needed
    - Fix any issues discovered
    - Document lessons learned
    - _Requirements: All_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
