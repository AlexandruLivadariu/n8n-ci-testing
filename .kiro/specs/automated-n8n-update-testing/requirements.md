# n8n Enterprise Deployment — Automated Testing, Update & Rollback Requirements

## 1. Introduction

This document defines the requirements for an automated system that keeps an enterprise n8n deployment secure, stable, and up-to-date without daily manual intervention. The system detects new n8n versions, runs a comprehensive test suite, applies updates safely, and rolls back automatically if anything breaks.

### 1.1 Problem Statement

- Security vulnerabilities in n8n keep appearing and patches must be applied quickly.
- There is no automated way to verify that n8n still works correctly after an update or configuration change.
- Checking n8n health manually every day is not sustainable.
- When an update breaks something, there is no defined rollback process.

### 1.2 Solution Overview

Three GitHub Actions workflows that work together:

1. **Update Pipeline** — Runs on a schedule (daily at 2 AM). Checks for new n8n versions, creates a backup, tests the update in isolation, applies it to production if tests pass, and rolls back automatically if tests fail.
2. **Code Change Pipeline** — Triggers on push/PR. Validates workflow changes and configuration against the test suite before merging.
3. **Daily Health Check Pipeline** — Runs on a schedule (daily at 8 AM). Executes a subset of tests against production to detect issues proactively.

All three pipelines share the same test suite but run different subsets of it.

### 1.3 Scope

This document covers:

- The complete test suite for verifying an n8n deployment (65 tests, 13 categories)
- The test workflows that must be pre-deployed inside n8n for the tests to work
- The three GitHub Actions pipelines (update, code change, health check)
- The backup and rollback mechanism
- Notification and reporting

This document does NOT cover:

- n8n workflow development practices or CI/CD for business workflows
- n8n initial installation and setup
- Infrastructure provisioning (servers, DNS, TLS certificates)

---

## 2. Glossary

| Term | Definition |
|------|-----------|
| **n8n_Instance** | The running n8n application container in production |
| **Test_Environment** | An isolated n8n instance (separate container + temporary database) used to validate updates before production |
| **Production_Environment** | The live n8n instance serving users |
| **Test_Suite** | The collection of 65 automated tests defined in this document |
| **Test_Workflow** | An n8n workflow specifically designed for testing, deployed inside n8n and triggered by the test suite |
| **Health_Check_Subset** | A smaller group of ~20 tests from the full suite, designed to run quickly (~3 min) for daily monitoring |
| **Rollback_Point** | A saved state consisting of: tagged Docker image + database backup + data volume backup |
| **Critical_Test** | A test whose failure triggers immediate automatic rollback (marked P0 in the test suite) |
| **Baseline** | A snapshot of metrics (response times, memory usage, workflow counts, credential counts) taken before an update, used for comparison after the update |
| **Self-Hosted Runner** | A GitHub Actions runner running on the same infrastructure as n8n, with Docker access |

---

## 3. Architecture

### 3.1 Infrastructure Assumptions

The system assumes the following infrastructure is already in place:

- n8n runs as a Docker container (via Docker Compose or standalone)
- PostgreSQL runs as a separate Docker container on the same host or network
- A GitHub repository contains: the docker-compose configuration, test scripts, test workflow JSON files, and GitHub Actions workflow YAML files
- A self-hosted GitHub Actions runner is deployed on the same machine as n8n (required for Docker access and localhost testing)
- SMTP is configured for sending email notifications
- n8n has a dedicated API key for test automation (read + write access)

### 3.2 System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Repository                         │
│                                                              │
│  /.github/workflows/                                         │
│    ├── update-pipeline.yml      (scheduled daily 2 AM)       │
│    ├── code-change-pipeline.yml (on push/PR)                 │
│    ├── health-check-pipeline.yml(scheduled daily 8 AM)       │
│                                                              │
│  /tests/                                                     │
│    ├── runner.sh                (main test runner script)     │
│    ├── config.yaml              (test configuration)         │
│    ├── lib/                     (test helper functions)       │
│    │   ├── infra.sh             (INF tests)                  │
│    │   ├── network.sh           (NET tests)                  │
│    │   ├── web.sh               (WEB tests)                  │
│    │   ├── auth.sh              (AUTH tests)                 │
│    │   ├── database.sh          (DB tests)                   │
│    │   ├── api.sh               (API tests)                  │
│    │   ├── workflows.sh         (WF tests)                   │
│    │   ├── credentials.sh       (CRED tests)                 │
│    │   ├── performance.sh       (PERF tests)                 │
│    │   ├── backup.sh            (BKP tests)                  │
│    │   ├── security.sh          (SEC tests)                  │
│    │   ├── notifications.sh     (NOTIF tests)                │
│    │   └── environment.sh       (ENV tests)                  │
│    └── results/                 (test output, gitignored)     │
│                                                              │
│  /test-workflows/                                            │
│    ├── health-check.json        (WF-001 webhook test)        │
│    ├── data-transform.json      (WF-002 expression test)     │
│    ├── http-request.json        (WF-003 outbound HTTP test)  │
│    ├── error-handling.json      (WF-004 error path test)     │
│    ├── cron-test.json           (WF-005 scheduled trigger)   │
│    ├── parent-workflow.json     (WF-006 sub-workflow caller)  │
│    └── child-workflow.json      (WF-006 sub-workflow callee)  │
│                                                              │
│  /scripts/                                                   │
│    ├── backup.sh                (create rollback point)       │
│    ├── rollback.sh              (restore from rollback point) │
│    ├── update.sh                (apply n8n update)            │
│    └── deploy-test-workflows.sh (import test workflows)       │
│                                                              │
│  docker-compose.yml                                          │
│  .env                           (not committed, secrets)      │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────────────┐    ┌──────────────────────────┐
│   n8n Production Container   │    │  PostgreSQL Container     │
│   - Port 5678                │◄──►│  - Port 5432              │
│   - /home/node/.n8n (volume) │    │  - /var/lib/pgdata (vol)  │
│   - Test workflows deployed  │    │                           │
└──────────────────────────────┘    └──────────────────────────┘

┌──────────────────────────────┐
│  GitHub Actions Self-Hosted   │
│  Runner                       │
│  - Docker access              │
│  - Same network as n8n        │
│  - Runs test suite            │
└──────────────────────────────┘
```

---

## 4. Requirements — Update Pipeline

### Requirement UP-1: Scheduled Update Detection

**User Story:** As a DevOps engineer, I want the system to automatically check for new n8n versions daily, so that security patches are identified without manual checking.

**Acceptance Criteria:**

1. THE Update Pipeline SHALL run as a GitHub Actions scheduled workflow (default: daily at 2:00 AM UTC, configurable via cron expression).
2. WHEN the pipeline runs, THE System SHALL query the Docker Hub API or n8n GitHub releases API for the latest n8n version tag.
3. WHEN a new version is found, THE System SHALL compare it against the currently deployed version (read from the running container via `docker inspect` or `n8n --version`).
4. IF the new version is higher than the current version, THEN THE System SHALL proceed to the backup and update process.
5. IF no new version is available, THEN THE System SHALL log "no update available" and exit successfully.
6. THE System SHALL also support manual trigger via `workflow_dispatch` with an optional `target_version` input parameter.
7. WHEN manually triggered with a `target_version`, THE System SHALL skip version detection and use the specified version.

### Requirement UP-2: Pre-Update Backup (Rollback Point Creation)

**User Story:** As a DevOps engineer, I want the system to create a complete backup before any update, so that I can restore the previous working state if the update fails.

**Acceptance Criteria:**

1. BEFORE any update is applied, THE System SHALL create a Rollback_Point.
2. WHEN creating a Rollback_Point, THE System SHALL tag the current running Docker image with a backup label (format: `n8n-backup-<YYYYMMDD-HHMMSS>`).
3. WHEN creating a Rollback_Point, THE System SHALL dump the PostgreSQL database to a compressed file (format: `n8n_db_<YYYYMMDD-HHMMSS>.sql.gz`) in the configured backup directory.
4. WHEN creating a Rollback_Point, THE System SHALL create a tarball of the n8n data volume (format: `n8n_data_<YYYYMMDD-HHMMSS>.tar.gz`).
5. WHEN creating a Rollback_Point, THE System SHALL verify all three backup artifacts exist and are non-empty.
6. WHEN creating a Rollback_Point, THE System SHALL calculate and record SHA256 checksums of all backup files.
7. IF any backup step fails, THEN THE System SHALL abort the entire update and send an alert notification.
8. THE System SHALL store rollback point metadata (version, timestamp, file paths, checksums) in a JSON manifest file.

### Requirement UP-3: Pre-Update Baseline Capture

**User Story:** As a DevOps engineer, I want the system to capture performance and state baselines before updating, so that I can compare against them after the update to detect regressions.

**Acceptance Criteria:**

1. AFTER the Rollback_Point is created, THE System SHALL run the full Test_Suite against the current (pre-update) production instance.
2. WHEN running pre-update tests, THE System SHALL record: all test pass/fail results, API response times (min, avg, max, p95 for each endpoint), memory usage of the n8n container, count of workflows (total and active), count of credentials, count of recent executions.
3. THE System SHALL save these baselines to a JSON file (format: `baseline_<YYYYMMDD-HHMMSS>.json`).
4. IF any Critical_Test fails during the pre-update run, THE System SHALL log a warning but continue with the update (the pre-update failure indicates a pre-existing issue, not an update regression).
5. THE System SHALL make the baseline available to post-update tests for comparison.

### Requirement UP-4: Update Execution

**User Story:** As a DevOps engineer, I want the system to apply n8n updates in a controlled manner with minimal downtime.

**Acceptance Criteria:**

1. WHEN pre-update baseline is captured, THE System SHALL pull the new n8n Docker image.
2. WHEN the image is downloaded, THE System SHALL stop the current n8n container gracefully (`docker stop` with a 30-second timeout).
3. WHEN the container is stopped, THE System SHALL start a new container using the updated image with the same environment variables, volumes, and network configuration.
4. WHEN the new container starts, THE System SHALL wait for n8n to be fully initialized by polling the `/healthz` endpoint every 5 seconds for up to 2 minutes.
5. IF n8n does not become healthy within 2 minutes, THE System SHALL trigger automatic rollback.
6. THE System SHALL complete the container swap within 5 minutes.

### Requirement UP-5: Post-Update Validation

**User Story:** As a DevOps engineer, I want the system to verify the update was successful by running the full test suite and comparing against the pre-update baseline.

**Acceptance Criteria:**

1. WHEN the updated n8n instance is healthy, THE System SHALL run the full Test_Suite.
2. WHEN post-update tests run, THE System SHALL compare all results against the pre-update baseline.
3. WHEN comparing, THE System SHALL flag: any test that changed from pass to fail, response time increases > 50%, memory usage increases > 100%.
4. WHEN post-update tests complete, THE System SHALL evaluate the Rollback Decision (see Requirement UP-6).
5. THE System SHALL generate a comparison report (pre vs post) and save it as a test artifact.

### Requirement UP-6: Automatic Rollback Decision

**User Story:** As a DevOps engineer, I want the system to automatically decide whether to keep the update or roll back, based on objective test results.

**Acceptance Criteria:**

1. AFTER post-update tests complete, THE System SHALL evaluate whether rollback is required.
2. THE System SHALL trigger automatic rollback if ANY of the following conditions are true:
   - Any test marked as Critical_Test (P0) fails
   - More than 30% of all tests fail
   - Average API response time increased by more than 50% compared to baseline
   - n8n container memory usage increased by more than 100% compared to baseline
3. IF rollback is triggered, THE System SHALL execute it within 2 minutes.
4. IF rollback is NOT triggered, THE System SHALL mark the update as successful.
5. THE System SHALL send an email notification with the decision (success or rollback) and detailed test results.

### Requirement UP-7: Rollback Execution

**User Story:** As a DevOps engineer, I want the system to restore the previous working state quickly and reliably when rollback is triggered.

**Acceptance Criteria:**

1. WHEN rollback is initiated, THE System SHALL stop the updated n8n container.
2. THE System SHALL restore the previous Docker image from the backup tag.
3. THE System SHALL restore the PostgreSQL database from the backup dump file.
4. THE System SHALL restore the n8n data volume from the backup tarball.
5. THE System SHALL start the n8n container with the previous image and restored data.
6. THE System SHALL wait for n8n to become healthy (poll `/healthz` for up to 2 minutes).
7. AFTER rollback completes, THE System SHALL run the Health_Check_Subset to verify the restored instance is functional.
8. IF the health check passes, THE System SHALL send a "rollback successful" notification.
9. IF the health check fails after rollback, THE System SHALL send a "CRITICAL: rollback failed" alert requiring immediate manual intervention.

---

## 5. Requirements — Code Change Pipeline

### Requirement CC-1: Trigger on Code Push

**User Story:** As a developer, I want the test suite to run automatically when I push workflow changes or configuration updates, so that I can catch issues before they reach production.

**Acceptance Criteria:**

1. THE Code Change Pipeline SHALL trigger on push to `main` branch and on pull request to `main` branch.
2. THE pipeline SHALL also trigger on `workflow_dispatch` for manual runs.
3. WHEN triggered, THE System SHALL run the Code Change test subset (all tests except PERF, BKP, and ENV categories).
4. THE System SHALL complete within 10 minutes.
5. WHEN tests complete, THE System SHALL report pass/fail as a GitHub commit status check.
6. IF run on a pull request, THE System SHALL post a comment with the test summary.

### Requirement CC-2: Test Workflow Validation

**User Story:** As a developer, I want the pipeline to validate that test workflow JSON files are valid before deploying them.

**Acceptance Criteria:**

1. WHEN test workflow JSON files are modified in the PR, THE System SHALL validate each file is valid JSON.
2. THE System SHALL verify each workflow JSON contains required fields: `name`, `nodes`, `connections`.
3. THE System SHALL verify each node in the workflow has required fields: `type`, `name`, `position`.
4. IF any validation fails, THE System SHALL fail the pipeline with a clear error message identifying the invalid file and field.

---

## 6. Requirements — Daily Health Check Pipeline

### Requirement HC-1: Scheduled Health Monitoring

**User Story:** As a DevOps engineer, I want automated daily health checks on production so that issues are detected proactively without manual monitoring.

**Acceptance Criteria:**

1. THE Health Check Pipeline SHALL run as a scheduled GitHub Actions workflow (default: daily at 8:00 AM UTC).
2. WHEN the pipeline runs, THE System SHALL execute the Health_Check_Subset against the Production_Environment.
3. THE Health_Check_Subset SHALL include: all INF tests (6), all NET tests (4), all WEB tests (5), DB-001, DB-003, DB-006, WF-001, WF-002, WF-008, and SEC-001, SEC-002.
4. THE Health_Check_Subset SHALL complete within 5 minutes.
5. IF all tests pass, THE System SHALL send a summary email ("n8n Health Check: All OK").
6. IF any test fails, THE System SHALL send an immediate alert email with failure details.
7. THE System SHALL also support manual trigger via `workflow_dispatch`.

---

## 7. Requirements — Test Suite

This section defines all 65 tests organized by category. Each test includes: ID, name, priority, criticality, and a technical description detailed enough to generate the test implementation.

### 7.1 Priority and Criticality Definitions

| Priority | Meaning | Pipeline Behavior |
|----------|---------|-------------------|
| **P0** | Must pass or rollback | Failure triggers automatic rollback (in Update Pipeline) or blocks merge (in Code Change Pipeline) |
| **P1** | Must pass or alert | Failure sends alert, blocks deployment, but does not trigger rollback on its own |
| **P2** | Should pass, advisory | Failure is logged and reported but does not block anything |

| Criticality | Meaning |
|-------------|---------|
| **CRITICAL** | Triggers immediate automatic rollback. No further tests run. |
| **HIGH** | Sends alert. Contributes to the 30% failure threshold for rollback. |
| **MEDIUM** | Logged and reported. Does not contribute to rollback decision. |

### 7.2 Test Category: Infrastructure & Container Health (INF)

> These tests run first in every pipeline. If any fail, all subsequent tests are skipped.

**INF-001: n8n Container Running State** | P0 / CRITICAL
Run `docker inspect --format={{.State.Status}} <n8n_container>` and verify output is `running`. If a HEALTHCHECK is defined, also verify `docker inspect --format={{.State.Health.Status}}` returns `healthy`. If the container is not running, capture the exit code and last 50 lines of logs (`docker logs --tail 50`) for diagnostics. Fail immediately if the container is not found or not running.

**INF-002: n8n Container Uptime Stability** | P0 / CRITICAL
Get the container start time via `docker inspect --format={{.State.StartedAt}}` and verify the container has been running for at least 30 seconds (to detect crash-restart loops). Get the restart count via `docker inspect --format={{.RestartCount}}` and verify it is 0 for post-update checks, or unchanged from the last recorded value for daily health checks. Store the restart count in a state file for future comparison.

**INF-003: PostgreSQL Container Health** | P0 / CRITICAL
Verify the PostgreSQL container status is `running` and health status is `healthy`. Additionally run `docker exec <postgres_container> pg_isready -U <db_user> -d <db_name>` and confirm exit code 0 with output containing "accepting connections". Timeout after 5 seconds.

**INF-004: Docker Network Connectivity** | P0 / CRITICAL
Verify the n8n container can reach the PostgreSQL container by running `docker exec <n8n_container> sh -c 'echo > /dev/tcp/<postgres_hostname>/5432'` from inside the n8n container. Verify the Docker network exists via `docker network inspect <network_name>`. Timeout after 5 seconds.

**INF-005: Docker Volume Mounts** | P1 / HIGH
Parse `docker inspect --format={{json .Mounts}} <n8n_container>` and verify expected volumes are mounted: n8n data volume at `/home/node/.n8n` (or configured path), and any custom nodes volume. For each mount, verify write access by touching and removing a test file. Similarly verify the PostgreSQL data volume.

**INF-006: Container Resource Usage** | P2 / MEDIUM
Run `docker stats --no-stream` for the n8n container. Parse memory usage (MB), CPU percentage, and memory percentage. Compare against configurable thresholds (default: memory < 80% of limit, CPU < 90%). For post-update checks, compare against pre-update baseline and flag if memory increased > 100% or CPU increased > 50%. Store current values as the new baseline.

### 7.3 Test Category: Network & Connectivity (NET)

**NET-001: n8n HTTP Port Accessibility** | P0 / CRITICAL
Send HTTP GET to the n8n base URL with `curl -s -o /dev/null -w '%{http_code},%{time_total}' --max-time 10 <n8n_url>`. Verify HTTP 200, response time < 5 seconds. If HTTPS, verify TLS certificate validity via `curl` ssl_verify_result = 0.

**NET-002: Webhook Endpoint Reachability** | P0 / CRITICAL
Send HTTP POST to the test webhook endpoint: `curl -s -X POST -H 'Content-Type: application/json' -d '{"test": "ping"}' --max-time 10 <n8n_url>/webhook/health-check`. Verify HTTP 200, response contains `{"status": "ok"}`, and response time < 3 seconds. Also test the `/webhook-test/` path.

**NET-003: External Network Connectivity** | P1 / HIGH
From inside the n8n container, make an outbound HTTPS request to a configurable target URL (default: `https://httpbin.org/get`). Verify HTTP 200 and valid JSON response. For air-gapped environments, configure a local HTTP echo server instead. If HTTP proxy is used, verify proxy environment variables are set inside the container.

**NET-004: Reverse Proxy / Load Balancer Health** | P1 / HIGH
Send a request through the public URL and verify proxy headers are present. Verify WebSocket upgrade support by sending upgrade headers — n8n editor requires WebSocket. If TLS termination is at the proxy, verify the certificate chain. Skip this test if no reverse proxy is configured (`PROXY_ENABLED=false`).

### 7.4 Test Category: Web Interface & UI (WEB)

**WEB-001: n8n Editor Page Load** | P0 / CRITICAL
HTTP GET to the n8n base URL. Verify HTTP 200, Content-Type contains `text/html`, response body contains n8n-specific markers (any of: `n8n`, `window.n8n`, `/assets/index-`), body size > 1KB, response time < 2 seconds. If auth is enabled, verify the response contains a login form.

**WEB-002: Static Assets Serving** | P1 / HIGH
Parse the HTML from WEB-001 to extract `<script src>` and `<link href>` URLs. For each of the first 5 assets, verify HTTP 200, non-zero size, and correct Content-Type. Broken assets mean the editor UI is non-functional.

**WEB-003: REST API Healthcheck Endpoint** | P0 / CRITICAL
GET `<n8n_url>/healthz` (or `/healthcheck`). Verify HTTP 200 and response body indicates healthy status. Try both endpoints — n8n versions differ in which they support.

**WEB-004: Version Verification** | P1 / HIGH
Verify the running n8n version matches the expected version. Query via API (`GET /api/v1/settings` with API key) or via Docker (`docker exec <container> n8n --version`). For post-update checks, the version must match the target update version. For daily checks, it must match the last deployed version stored in the state file.

**WEB-005: WebSocket Connection** | P1 / HIGH
Open a WebSocket connection to `ws(s)://<n8n_host>/rest/push`. Verify the handshake completes (HTTP 101 Switching Protocols) and the connection stays open for at least 5 seconds. Include authentication if required. The n8n editor requires WebSocket for real-time updates.

### 7.5 Test Category: Authentication & Authorization (AUTH)

**AUTH-001: API Key Authentication** | P0 / CRITICAL
Send `GET /api/v1/workflows` with a valid API key header. Verify HTTP 200 and valid JSON response with a `data` array. Then send the same request with an invalid API key and verify HTTP 401. This tests both positive (valid key works) and negative (invalid key rejected) authentication.

**AUTH-002: User Login** | P1 / HIGH
POST to `/api/v1/login` with test user credentials. Verify HTTP 200 and a session token is returned. Use the token to call `GET /api/v1/me` and verify user profile is returned. Then test with invalid credentials — verify HTTP 401. Verify rate limiting is active by sending 10 rapid failed login attempts with a throwaway email.

**AUTH-003: RBAC Permission Enforcement** | P1 / HIGH
With a "viewer" role test user: verify GET /api/v1/workflows succeeds (read) but POST and DELETE are rejected (403). With an "editor" role: verify create succeeds but user management is rejected. With admin API key: verify full access. If Enterprise projects are enabled, verify a user in Project A cannot see workflows in Project B.

**AUTH-004: Unauthenticated Access Prevention** | P1 / HIGH
Send requests WITHOUT any authentication to: `/api/v1/workflows`, `/api/v1/credentials`, `/api/v1/executions`, `/api/v1/users`. All must return 401. Verify error responses do not leak data (no workflow names, credential values, or user emails). Verify `/healthz` remains publicly accessible.

**AUTH-005: SSO Integration** | P1 / HIGH
Skip if SSO is not configured. For SAML: verify the metadata endpoint returns valid XML. For LDAP: verify connection. For OAuth: verify callback URL is not 404. Verify SSO-created users get the correct default role.

### 7.6 Test Category: Database & Data Integrity (DB)

**DB-001: Database Connection and Query** | P0 / CRITICAL
Execute `SELECT count(*) FROM workflow_entity;` via psql inside the PostgreSQL container. Verify: query succeeds, result is a valid integer >= 0, completes within 1 second. Also count `credential_entity` and `execution_entity`. Compare counts against pre-update baseline — if workflow count dropped to 0 from a non-zero baseline, flag as data loss.

**DB-002: Schema Migration Verification** | P0 / CRITICAL
Query the migrations table (`SELECT name, timestamp FROM migrations ORDER BY timestamp DESC LIMIT 10;`). Verify no errors. List all tables in the public schema and compare against a known-good list for the current n8n version. Verify key columns exist in `workflow_entity`: id, name, active, nodes, connections, createdAt, updatedAt.

**DB-003: Workflow Data Integrity** | P0 / CRITICAL
Query a sample of workflows: `SELECT id, name, nodes FROM workflow_entity LIMIT 5;`. For each row, parse the `nodes` column as JSON and verify it is a valid array where each element has `type`, `name`, and `position` keys. Verify `SELECT count(*) FROM workflow_entity WHERE nodes IS NULL;` returns 0. If a known test workflow exists, verify its structure matches the expected fixture.

**DB-004: Credential Encryption Verification** | P1 / HIGH
Query `SELECT id, name, type, data FROM credential_entity LIMIT 3;`. Verify the `data` column is NOT plaintext JSON — it should be encrypted. Search for common plaintext patterns (`password:`, `apiKey:`, `token:`, `secret:`) in the data column; finding these means the encryption key may be missing or changed. Verify the API (GET /api/v1/credentials) does not expose decrypted data.

**DB-005: Query Performance** | P2 / MEDIUM
Run `EXPLAIN ANALYZE` on three representative queries (count workflows, select active workflows, count finished executions). Record execution times and compare against baseline. Flag if any query takes > 2x baseline time. Verify expected indexes exist on `execution_entity` (especially on workflowId, finished, startedAt).

**DB-006: Connection Pool Health** | P1 / HIGH
Query `pg_stat_activity` to get total connections, active connections, and idle connections for the n8n database. Verify total < `max_connections`. Check for `idle in transaction` connections older than 60 seconds (indicates connection leaks). Verify active connections < 50% of max.

### 7.7 Test Category: API Endpoints (API)

**API-001: List Workflows** | P0 / CRITICAL
GET `/api/v1/workflows` with API key. Verify HTTP 200, valid JSON with `data` array, each workflow object has id/name/active/createdAt/updatedAt, response time < 3 seconds. Test filtering with `?active=true` and `?limit=1`.

**API-002: Workflow CRUD Cycle** | P0 / CRITICAL
Create a test workflow via POST (`name: "[TEST] CRUD - <timestamp>"`, single manualTrigger node). Verify 200/201 with `id` returned. Read it via GET. Update the name via PATCH. Delete via DELETE. Verify GET after delete returns 404. Always clean up the test workflow in a finally block.

**API-003: Workflow Activation/Deactivation** | P1 / HIGH
Create a test workflow with a Webhook trigger node (required for activation). Activate via PATCH with `{"active": true}`. Verify state persists via GET. Deactivate. Clean up.

**API-004: Execution History** | P1 / HIGH
GET `/api/v1/executions`. Verify valid JSON with `data` array, execution objects have id/finished/mode/startedAt/stoppedAt/workflowId, response time < 5 seconds. Test filtering by status and pagination with limit+cursor.

**API-005: Credentials API** | P1 / HIGH
GET `/api/v1/credentials`. Verify valid JSON. Verify the response does NOT include decrypted `data` fields. Verify GET `/api/v1/credential-types` returns available types.

**API-006: Error Handling and Rate Limiting** | P2 / MEDIUM
GET a non-existent endpoint — verify 404 with structured JSON (no stack traces, no file paths). POST with malformed JSON — verify 400. If rate limiting is configured, send 100 rapid requests and verify 429 is returned.

### 7.8 Test Category: Workflow Execution (WF)

> These tests require pre-deployed test workflows inside n8n. See Section 9 for the test workflow specifications.

**WF-001: Basic Webhook Test** | P0 / CRITICAL
POST `{"test_id": "WF-001", "timestamp": "<now>"}` to `/webhook/health-check`. Verify HTTP 200, response JSON contains `{"status": "ok", "received": true}` and the original timestamp. Verify response time < 3 seconds. Wait 2 seconds, then verify the execution appears in execution history via the API.

**WF-002: Data Transformation** | P0 / CRITICAL
POST `{"items": [{"name": "test", "value": 42}, {"name": "check", "value": 99}]}` to `/webhook/test-transform`. The workflow sums values, counts items, and uppercases names. Verify response: `{"sum": 141, "count": 2, "names": ["TEST", "CHECK"]}`. This tests the n8n expression engine and Code node JavaScript execution.

**WF-003: HTTP Request Node** | P1 / HIGH
POST to `/webhook/test-http`. The workflow makes an outbound GET to a configurable URL (default: httpbin.org/get) and returns the result. Verify the outbound request succeeded and response data is present. Tests n8n's ability to call external APIs.

**WF-004: Error Handling** | P1 / HIGH
POST `{"trigger_error": false}` to `/webhook/test-error` — verify success response. POST `{"trigger_error": true}` — verify the error handler caught it and returned error details (not a raw 500). POST `{"trigger_error": false}` again — verify n8n still works after a handled error.

**WF-005: Scheduled Trigger Verification** | P1 / HIGH
Activate a test workflow with a 1-minute cron trigger. Wait 90 seconds. Query execution history for this workflow — verify at least 1 execution with status "success" and mode "trigger". Deactivate and clean up.

**WF-006: Sub-Workflow Execution** | P1 / HIGH
POST `{"value": 21}` to `/webhook/test-subworkflow`. The parent workflow calls a child workflow via Execute Workflow node. The child doubles the value. Verify response contains value 42. Verify both parent and child executions appear in history.

**WF-007: Parallel Execution** | P2 / MEDIUM
Send 10 parallel POST requests to `/webhook/health-check`. Verify all 10 return HTTP 200 with valid JSON, max response time < 10 seconds, and all 10 executions appear in history.

**WF-008: Production Workflow Smoke Test** | P0 / CRITICAL
GET `/api/v1/workflows?active=true` and compare the active workflow list against the pre-update baseline. Verify: count matches, each previously active workflow is still active, no unexpected deactivations. For each active workflow, verify it can be retrieved and its `nodes` field is valid JSON.

### 7.9 Test Category: Credential & Secrets Management (CRED)

**CRED-001: Credential Decryption** | P0 / CRITICAL
This is one of the most important tests. If the `N8N_ENCRYPTION_KEY` changed or is missing after an update, ALL credentials become unreadable. Trigger the test credential workflow (which uses a test credential to authenticate against a known endpoint). Verify no "Credentials could not be decrypted" error and the authenticated request succeeds. Also verify GET `/api/v1/credentials/<test_id>` returns 200 (not 500).

**CRED-002: Credential Count Consistency** | P1 / HIGH
GET `/api/v1/credentials` and count results. Compare against pre-update baseline. Verify count matches or exceeds baseline, each baseline credential still exists (by ID), and types are preserved.

**CRED-003: Environment Variables Integrity** | P1 / HIGH
Run `docker exec <n8n_container> env` and verify presence (NOT values) of: `N8N_ENCRYPTION_KEY` (non-empty), `DB_TYPE` (= "postgresdb"), `DB_POSTGRESDB_HOST`, `DB_POSTGRESDB_DATABASE`, `N8N_HOST`, `WEBHOOK_URL`, `N8N_PROTOCOL` (= "https" for production). Never log the actual values of sensitive variables.

**CRED-004: Credential Sharing** | P2 / MEDIUM
Enterprise feature. Verify credential sharing permissions are preserved. Check `sharedWith` field on shared credentials. Verify scoped access (user with access can see it, user without cannot). Skip if Enterprise features are not enabled.

### 7.10 Test Category: Performance & Load (PERF)

> Only runs in the Update Pipeline.

**PERF-001: API Response Time Benchmark** | P1 / HIGH
Execute 10 iterations of GET requests to `/api/v1/workflows`, `/api/v1/executions?limit=10`, `/api/v1/credentials`, and POST to `/webhook/health-check`. Calculate min, avg, max, p95 for each. Compare against baseline. Flag if any average increased > 50%.

**PERF-002: Workflow Execution Time Benchmark** | P1 / HIGH
Execute WF-002 (data transform) 10 times. Record both external round-trip time (curl) and internal execution time (from execution history). Calculate avg, p95, max. Compare against baseline. Flag if avg increased > 50%.

**PERF-003: Memory Usage Under Load** | P1 / HIGH
Record initial memory from `docker stats`. Execute 50 sequential webhook requests. Wait 10 seconds for garbage collection. Record post-load memory. Flag as potential memory leak if memory increased > 100% and did not recover. Compare absolute usage against baseline — flag if > 100% increase (triggers rollback per UP-6).

**PERF-004: Database Connection Stress** | P2 / MEDIUM
Send 20 parallel webhook requests while monitoring `pg_stat_activity` every 2 seconds. Verify connections stay below max, no "too many connections" errors, and connections are released after completion.

**PERF-005: Large Payload Processing** | P2 / MEDIUM
Send a ~1MB JSON payload (10,000 objects with 5 fields each) to WF-002. Verify n8n processes without crashing, responds within 30 seconds, and remains healthy afterward.

### 7.11 Test Category: Backup & Rollback Verification (BKP)

> Only runs in the Update Pipeline.

**BKP-001: Backup Completeness** | P0 / CRITICAL (blocks update)
Verify all backup artifacts exist and are valid: Docker image tag exists (`docker image inspect`), database dump is a valid gzip (`gzip -t`), volume tarball is non-empty. Count tables in the database dump (`zcat | grep 'CREATE TABLE' | wc -l`). This runs BEFORE the update — if it fails, the update is aborted.

**BKP-002: Database Backup Restorability** | P1 / HIGH
Create a temporary test database, restore the backup into it, verify workflow count matches the pre-backup count, then drop the test database. This proves the backup is not corrupted. Always clean up the test database.

**BKP-003: Docker Image Rollback Capability** | P1 / HIGH
Verify the backup Docker image exists and can start: `docker run --rm -d --name n8n_rollback_test <backup_tag> sleep 5`, then `docker exec n8n_rollback_test n8n --version` should return the expected previous version. Clean up.

**BKP-004: Backup Retention** | P2 / MEDIUM
List backup files and verify: backups older than retention period (default: 30 days) are cleaned up, at least 3 most recent are retained, total disk usage is within configured limits.

### 7.12 Test Category: Security & Compliance (SEC)

**SEC-001: TLS Configuration** | P1 / HIGH
Use `openssl s_client` to verify: TLS 1.2+ (reject 1.0/1.1), certificate not expired (warn if < 30 days), hostname matches, complete chain, no weak ciphers. Verify HSTS header. Skip if `HTTPS_ENABLED=false`.

**SEC-002: Security Headers** | P1 / HIGH
Verify response headers include: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` or `SAMEORIGIN`, `Content-Security-Policy` (present), `Referrer-Policy` (present). Verify the `Server` header does not expose the n8n version. Verify cookies have `Secure` and `HttpOnly` flags.

**SEC-003: CVE Vulnerability Scan** | P1 / HIGH
Scan the n8n Docker image using Trivy (or Docker Scout / Grype). Count critical and high vulnerabilities with available fixes. Compare against pre-update scan — the update must not introduce NEW critical CVEs. If the update is a security patch, verify the targeted CVEs are resolved.

**SEC-004: Node Package Integrity** | P1 / HIGH
List installed n8n node packages inside the container and compare the count against the expected count for this version. If custom community nodes are installed, verify they are still present. Flag unexpected packages.

**SEC-005: Container Security** | P1 / HIGH
Via `docker inspect`, verify: container is NOT running as root (User is set), no privileged mode, no host network mode, memory limits are set, `docker.sock` is not mounted.

**SEC-006: Execution Data Cleanup** | P2 / MEDIUM
Verify `EXECUTIONS_DATA_PRUNE=true` is set. Query execution_entity to confirm no executions exist older than the configured max age. Verify execution count is not growing unbounded.

### 7.13 Test Category: Notification & Alerting (NOTIF)

> Only runs in the Update Pipeline.

**NOTIF-001: Email Delivery** | P1 / HIGH
Send a test email via SMTP to configured recipients. Verify SMTP connection succeeds and email is accepted (SMTP 250). If a test mailbox is available, verify delivery within 30 seconds.

**NOTIF-002: Alert Channel Verification** | P2 / MEDIUM
Validate all configured recipient email addresses. If Slack webhook is configured, send a test message and verify HTTP 200. Verify at least 2 notification recipients are configured.

**NOTIF-003: n8n Error Workflow** | P2 / MEDIUM
Verify an Error Workflow is configured in n8n settings. Trigger a deliberate error in a test workflow. Verify the Error Workflow executed (check execution history). Verify the error notification was sent.

### 7.14 Test Category: Multi-Instance & Environment (ENV)

> Only runs in the Update Pipeline. Skip if single instance.

**ENV-001: Instance Configuration Consistency** | P1 / HIGH
For each configured n8n instance: verify reachable at URL, running expected version, name matches config, has its own database. Generate a comparison matrix.

**ENV-002: Environment Parity** | P1 / HIGH
Compare test environment vs production: n8n version, Node.js version, PostgreSQL version, key environment variable presence, custom community nodes, Docker image tag. Log all differences.

**ENV-003: Source Control Integration** | P1 / HIGH
Verify Git is connected and branch is correct. If production is "Protected" mode, verify direct editing is blocked. Verify last Git pull was successful and recent.

---

## 8. Requirements — Notifications and Reporting

### Requirement NR-1: Email Notifications

**Acceptance Criteria:**

1. THE System SHALL send email notifications for the following events:
   - Update detected (informational)
   - Update starting (informational)
   - Update succeeded — all tests passed (success)
   - Rollback triggered — tests failed (alert, immediate)
   - Rollback completed (informational)
   - Rollback FAILED (critical alert)
   - Daily health check passed (summary)
   - Daily health check failed (alert, immediate)
2. THE System SHALL support configuring multiple email recipients.
3. Alert emails (rollback, health check failure) SHALL include: which tests failed, error messages, response time comparisons, and the n8n version involved.
4. THE System SHALL use GitHub Actions' built-in secrets for SMTP credentials.

### Requirement NR-2: Test Reports

**Acceptance Criteria:**

1. AFTER each pipeline run, THE System SHALL generate a JSON test report containing: pipeline name, timestamp, n8n version, each test's ID/name/status/duration/error, overall pass/fail/skip counts, and the rollback decision (if applicable).
2. THE System SHALL upload the test report as a GitHub Actions artifact.
3. THE System SHALL retain test reports for at least 90 days (via GitHub artifact retention settings).
4. FOR the Update Pipeline, the report SHALL also include: pre-update vs post-update comparison data.

### Requirement NR-3: Audit Logging

**Acceptance Criteria:**

1. THE System SHALL log all significant events to a persistent log file on the host (not just GitHub Actions logs, which expire).
2. Events to log: update detection, backup creation, update application, each test result, rollback decisions, rollback execution, manual triggers.
3. Each log entry SHALL include: timestamp, event type, n8n version, details, and who/what initiated the action.
4. THE System SHALL retain audit logs for at least 1 year.

---

## 9. Test Workflow Specifications

These n8n workflows must be deployed inside the n8n instance for the test suite to work. They are stored as JSON files in the `/test-workflows/` directory of the repository and deployed via the n8n API during initial setup or via the `deploy-test-workflows.sh` script.

### 9.1 [TEST] Webhook Health Check (used by WF-001)

```
Trigger:        Webhook node
                - Method: POST
                - Path: /health-check
                - Authentication: None
                - Response Mode: "Last Node"

Node 1:         Set node
                - Assigns: status = "ok", received = true
                - Passes through: all input fields (test_id, timestamp)

Node 2:         Respond to Webhook node
                - Returns: all fields from Set node as JSON

Expected input:  {"test_id": "WF-001", "timestamp": "2025-01-15T10:30:00Z"}
Expected output: {"status": "ok", "received": true, "test_id": "WF-001", "timestamp": "2025-01-15T10:30:00Z"}
```

### 9.2 [TEST] Data Transform (used by WF-002)

```
Trigger:        Webhook node
                - Method: POST
                - Path: /test-transform
                - Authentication: None
                - Response Mode: "Last Node"

Node 1:         Code node (JavaScript)
                - Receives: {"items": [{"name": "...", "value": N}, ...]}
                - Logic:
                    const items = $input.first().json.items;
                    const sum = items.reduce((acc, i) => acc + i.value, 0);
                    const count = items.length;
                    const names = items.map(i => i.name.toUpperCase());
                    return [{json: {sum, count, names, processed_at: new Date().toISOString()}}];

Node 2:         Respond to Webhook node

Expected input:  {"items": [{"name": "test", "value": 42}, {"name": "check", "value": 99}]}
Expected output: {"sum": 141, "count": 2, "names": ["TEST", "CHECK"], "processed_at": "..."}
```

### 9.3 [TEST] HTTP Request (used by WF-003)

```
Trigger:        Webhook node
                - Method: POST
                - Path: /test-http
                - Authentication: None
                - Response Mode: "Last Node"

Node 1:         HTTP Request node
                - Method: GET
                - URL: https://httpbin.org/get (configurable via n8n variable)
                - Timeout: 10 seconds

Node 2:         Set node
                - Assigns: external_call_success = true, external_status = {{$json.status}} or similar

Node 3:         Respond to Webhook node

Expected output: {"external_call_success": true, ...response data from httpbin...}
```

### 9.4 [TEST] Error Handling (used by WF-004)

```
Trigger:        Webhook node
                - Method: POST
                - Path: /test-error
                - Authentication: None
                - Response Mode: "Last Node"

Node 1:         Code node (JavaScript)
                - Settings: continueOnFail = true (or use error output)
                - Logic:
                    if ($input.first().json.trigger_error) {
                      throw new Error("Intentional test error");
                    }
                    return [{json: {status: "ok", error_triggered: false}}];
                - Success output → Node 2
                - Error output → Node 3

Node 2:         Respond to Webhook node (success path)
                - Returns: {status: "ok", error_triggered: false}

Node 3:         Set node (error path)
                - Assigns: status = "error_handled", error_triggered = true,
                           error_message = {{$json.error.message}}

Node 4:         Respond to Webhook node (error path)
                - Returns: {status: "error_handled", error_triggered: true, error_message: "..."}

Expected input (success):  {"trigger_error": false}
Expected output (success): {"status": "ok", "error_triggered": false}
Expected input (error):    {"trigger_error": true}
Expected output (error):   {"status": "error_handled", "error_triggered": true, "error_message": "Intentional test error"}
```

### 9.5 [TEST] Cron Test (used by WF-005)

```
Trigger:        Cron node
                - Expression: * * * * * (every minute)
                - NOTE: This workflow should be INACTIVE by default.
                        The test activates it, waits, checks, then deactivates it.

Node 1:         Set node
                - Assigns: executed_at = {{$now.toISO()}}, test = "cron"

Node 2:         No-Op / Stop (does not need to respond since there is no webhook)

Purpose:        This workflow exists solely to verify the cron scheduling engine works.
                The test checks execution_entity for entries with this workflow's ID.
```

### 9.6 [TEST] Parent Workflow (used by WF-006)

```
Trigger:        Webhook node
                - Method: POST
                - Path: /test-subworkflow
                - Authentication: None
                - Response Mode: "Last Node"

Node 1:         Execute Workflow node
                - Workflow ID: <child_workflow_id> (configured during deployment)
                - Mode: "Wait for Sub-Workflow Completion"
                - Input: passes through the incoming {"value": N}

Node 2:         Set node
                - Assigns: parent_processed = true
                - Passes through: all fields from child workflow response

Node 3:         Respond to Webhook node

Expected input:  {"value": 21}
Expected output: {"doubled_value": 42, "parent_processed": true}
```

### 9.7 [TEST] Child Workflow (used by WF-006)

```
Trigger:        Execute Workflow Trigger node
                - (Triggered by parent, not by webhook)

Node 1:         Code node
                - Logic:
                    const value = $input.first().json.value;
                    return [{json: {doubled_value: value * 2}}];

Output:         Returns {"doubled_value": 42} to the parent workflow
```

### 9.8 [TEST] Credential Test (used by CRED-001)

```
Trigger:        Webhook node
                - Method: POST
                - Path: /test-credential
                - Authentication: None
                - Response Mode: "Last Node"

Node 1:         HTTP Request node
                - Method: GET
                - URL: https://httpbin.org/basic-auth/testuser/testpass
                - Authentication: Use "test-credential" (HTTP Basic Auth type)
                - Credential: pre-configured with username "testuser", password "testpass"

Node 2:         Set node
                - Assigns: credential_works = true if HTTP request returned 200
                           credential_works = false if it returned 401 or error

Node 3:         Respond to Webhook node

Expected output (success): {"credential_works": true, "authenticated": true}
Expected output (failure): {"credential_works": false, "error": "Credentials could not be decrypted"}

Purpose:        Verifies that the N8N_ENCRYPTION_KEY is intact and credentials can be decrypted.
```

---

## 10. Configuration

### 10.1 Test Configuration File

All configurable values for the test suite are stored in `/tests/config.yaml`:

```yaml
# n8n connection
n8n:
  url: "https://n8n.example.com"
  container_name: "n8n-production"
  api_key_env: "N8N_TEST_API_KEY"       # GitHub secret name

# PostgreSQL
postgres:
  container_name: "n8n-postgres"
  db_name: "n8n"
  db_user: "n8n"
  password_env: "N8N_DB_PASSWORD"        # GitHub secret name

# Rollback thresholds
thresholds:
  critical_test_failure: true             # any P0 failure = rollback
  test_failure_percent: 30                # >30% failure = rollback
  response_time_increase_percent: 50      # >50% avg increase = rollback
  memory_increase_percent: 100            # >100% increase = rollback
  container_startup_timeout_seconds: 120
  container_min_uptime_seconds: 30

# Backup
backup:
  directory: "/backups/n8n"
  retention_days: 30
  min_retained_count: 3

# Notifications
notifications:
  smtp_host_env: "SMTP_HOST"
  smtp_port: 587
  smtp_user_env: "SMTP_USER"
  smtp_password_env: "SMTP_PASSWORD"
  recipients:
    - "devops-team@example.com"
    - "oncall@example.com"

# Feature flags (skip tests that don't apply)
features:
  https_enabled: true
  proxy_enabled: true
  sso_enabled: false
  enterprise_features_enabled: true
  multi_instance_enabled: false
  source_control_enabled: true

# External test target (for NET-003, WF-003)
external_test_url: "https://httpbin.org/get"

# State storage (for baselines and counts)
state_directory: "/var/lib/n8n-tests"

# Test workflows (IDs populated after deployment)
test_workflows:
  health_check:
    name: "[TEST] Webhook Health Check"
    webhook_path: "/webhook/health-check"
    id: ""                                # set after deploy
  data_transform:
    name: "[TEST] Data Transform"
    webhook_path: "/webhook/test-transform"
    id: ""
  http_request:
    name: "[TEST] HTTP Request"
    webhook_path: "/webhook/test-http"
    id: ""
  error_handling:
    name: "[TEST] Error Handling"
    webhook_path: "/webhook/test-error"
    id: ""
  cron_test:
    name: "[TEST] Cron Test"
    id: ""
  parent_workflow:
    name: "[TEST] Parent Workflow"
    webhook_path: "/webhook/test-subworkflow"
    id: ""
  child_workflow:
    name: "[TEST] Child Workflow"
    id: ""
  credential_test:
    name: "[TEST] Credential Test"
    webhook_path: "/webhook/test-credential"
    id: ""
```

### 10.2 GitHub Secrets Required

| Secret Name | Purpose |
|------------|---------|
| `N8N_TEST_API_KEY` | API key for n8n with read+write access |
| `N8N_DB_PASSWORD` | PostgreSQL password for the n8n database |
| `SMTP_HOST` | SMTP server hostname |
| `SMTP_USER` | SMTP authentication username |
| `SMTP_PASSWORD` | SMTP authentication password |
| `SLACK_WEBHOOK_URL` | (Optional) Slack webhook for alerts |

---

## 11. Pipeline Execution Details

### 11.1 Update Pipeline — GitHub Actions Workflow

**Trigger:** `schedule: cron '0 2 * * *'` and `workflow_dispatch` with optional `target_version` input.

**Steps:**

1. **Detect** — Query Docker Hub for latest n8n tag. Compare against running version. Exit if no update.
2. **Backup** — Tag current image, dump database, tar data volume. Run BKP-001 to verify.
3. **Baseline** — Run full test suite against current production. Save results as baseline JSON.
4. **Update** — Pull new image, stop old container, start new container, wait for healthy.
5. **Validate** — Run full test suite against updated production. Compare against baseline.
6. **Decide** — Evaluate rollback criteria. If rollback needed, go to step 7. If not, go to step 8.
7. **Rollback** — Stop updated container, restore image + database + volume, start old container, run health check subset to verify.
8. **Report** — Generate comparison report, send email notification, upload artifacts.

**Estimated duration:** 15–20 minutes (including backup, two full test runs, and update).

### 11.2 Code Change Pipeline — GitHub Actions Workflow

**Trigger:** `push` to main, `pull_request` to main, `workflow_dispatch`.

**Steps:**

1. **Validate** — If test workflow JSON files were modified, validate their structure.
2. **Test** — Run the Code Change test subset (INF, NET, WEB, AUTH, DB, API, WF, CRED, SEC-001/002).
3. **Report** — Post results as commit status. If PR, post a summary comment.

**Estimated duration:** 5–7 minutes.

### 11.3 Health Check Pipeline — GitHub Actions Workflow

**Trigger:** `schedule: cron '0 8 * * *'` and `workflow_dispatch`.

**Steps:**

1. **Test** — Run Health_Check_Subset (INF, NET, WEB, DB-001/003/006, WF-001/002/008, SEC-001/002).
2. **Report** — Send summary email (pass) or alert email (fail). Upload artifacts.

**Estimated duration:** 2–3 minutes.

### 11.4 Test Execution Order

Tests run in phases. If a CRITICAL test fails in any phase, all subsequent phases are skipped.

| Phase | Tests | Can Parallelize? |
|-------|-------|-----------------|
| 1. Infrastructure | INF-001 → INF-006 | No (sequential, each depends on previous) |
| 2. Network & Web | NET-001 → NET-004 → WEB-001 → WEB-005 | No |
| 3. Auth & Database | AUTH-001 → AUTH-005 and DB-001 → DB-006 | Yes (two parallel groups) |
| 4. API & Workflows | API-001 → API-006 → WF-001 → WF-008 | No |
| 5. Credentials | CRED-001 → CRED-004 | No |
| 6. Performance | PERF-001 → PERF-005 | No (Update Pipeline only) |
| 7. Backup | BKP-001 → BKP-004 | No (Update Pipeline only) |
| 8. Security | SEC-001 → SEC-006 | Partially |
| 9. Notifications | NOTIF-001 → NOTIF-003 | No (Update Pipeline only) |
| 10. Environment | ENV-001 → ENV-003 | No (Update Pipeline only, if multi-instance) |

---

## 12. Manual Override Commands

THE System SHALL support the following manual operations via `workflow_dispatch` inputs on the Update Pipeline:

| Command | Input | Behavior |
|---------|-------|----------|
| Check for update only | `action: check` | Detect new version but do not apply. Report findings. |
| Apply specific version | `action: update`, `target_version: 1.72.0` | Skip detection, apply the specified version. |
| Run tests only | `action: test` | Run full test suite against current production without updating. |
| Rollback to last backup | `action: rollback` | Restore from the most recent Rollback_Point. |
| Rollback to specific point | `action: rollback`, `rollback_id: 20250115-020000` | Restore from a specific named Rollback_Point. |
| Deploy test workflows | `action: deploy-workflows` | Import/update all test workflows into n8n via the API. |

---

## 13. Non-Functional Requirements

### 13.1 Performance

- Full test suite SHALL complete within 10 minutes.
- Health check subset SHALL complete within 5 minutes.
- Rollback SHALL complete within 2 minutes.
- Container update (stop old + start new + healthy) SHALL complete within 5 minutes.

### 13.2 Reliability

- IF a test script itself crashes (not an n8n failure), THE System SHALL catch the error, log it, and continue with remaining tests rather than aborting the entire pipeline.
- IF the GitHub Actions runner loses connectivity during an update, the n8n container should still be running (either old or new version). The pipeline should detect the inconsistent state on the next run.

### 13.3 Security

- API keys, database passwords, and SMTP credentials SHALL be stored as GitHub Actions encrypted secrets, never in code or config files.
- Test scripts SHALL never log the values of sensitive environment variables.
- The test API key SHALL have the minimum permissions necessary (read access to all resources, write access only for creating/deleting test workflows).

### 13.4 Retention

- Test reports (GitHub Actions artifacts): 90 days.
- Backup files: configurable, default 30 days, minimum 3 retained.
- Audit logs: 1 year.
- Pre-update baselines: keep the last 30 baselines.

---

## 14. Future Considerations

These items are out of scope for the initial implementation but should be considered for future iterations:

- **Blue-green / canary deployment**: Run the new version alongside the old one and gradually shift traffic, rather than a direct container swap.
- **Kubernetes migration**: If the deployment moves from Docker Compose to Kubernetes, the backup/restore and container management scripts will need to be rewritten for kubectl/Helm.
- **Observability integration**: Feed test results and performance baselines into Prometheus/Grafana for long-term trending and alerting.
- **Workflow-level testing**: Beyond testing that n8n works, test that specific business workflows produce correct outputs (requires business-specific test fixtures).
- **Third-party connector monitoring**: Automatically test when upstream APIs or n8n community node packages release new versions that might affect existing workflows.